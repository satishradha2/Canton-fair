import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../data/field_work_repository.dart';
import '../data/visit_ai_service.dart';
import 'visit_audio_player_screen.dart';

class VisitRecordingScreen extends StatefulWidget {
  const VisitRecordingScreen({super.key, required this.scope,
    required this.visitId, required this.supplierName, this.reviewOnly = false});
  final String scope;
  final int visitId;
  final String supplierName;
  final bool reviewOnly;
  @override
  State<VisitRecordingScreen> createState() => _VisitRecordingScreenState();
}

class _VisitRecordingScreenState extends State<VisitRecordingScreen>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _repository = FieldWorkRepository();
  final _notes = TextEditingController();
  final _elapsed = Stopwatch();
  Timer? _timer;
  Map<String, Object?>? _pending;
  String _kind = 'conversation';
  String? _error;
  bool _consent = false;
  bool _recording = false;
  bool _busy = false;
  bool _foreground = true;
  int _saved = 0;
  final _ai = VisitAiService();
  List<Map<String, Object?>> _segments = [];
  String _language = 'English';
  String? _progress;
  bool _loadingSegments = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSegments());
  }

  Future<void> _loadSegments() async {
    if (mounted) setState(() => _loadingSegments = true);
    try {
      final rows = await _ai.recordings(widget.scope, widget.visitId);
      if (mounted) setState(() => _segments = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingSegments = false);
    }
  }

  Future<void> _process(Map<String, Object?> row, bool transcribe) async {
    final allowed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(transcribe ? 'Send audio for transcription?' : 'Translate and summarize?'),
      content: Text(transcribe
        ? 'This sends the saved audio to OpenAI through Supabase. Confirm you have permission to upload it. Online processing may incur charges. The original stays on this device.'
        : 'This sends the saved transcript to OpenAI. The report is an AI suggestion requiring review, not a verified or guaranteed-complete record.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
    if (allowed != true || !mounted || _busy || _pending != null) return;
    setState(() { _busy = true; _error = null;
      _progress = transcribe ? 'Transcribing audio...' : 'Translating and preparing report...'; });
    try {
      await _ai.process(widget.scope, row, transcribe: transcribe, language: _language);
      await _loadSegments();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() { _busy = false; _progress = null; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _recording && !_busy) unawaited(_stop());
  }

  Future<void> _start() async {
    if (widget.reviewOnly || _busy || _pending != null || !_consent) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _recorder.hasPermission()) throw StateError('Microphone permission is required.');
      _pending = await _repository.prepareRecording(widget.scope, widget.visitId, _kind);
      if (!_foreground) throw StateError('Return to this screen before starting audio.');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _pending!['path'] as String);
      _recording = true;
      _elapsed..reset()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (error) {
      _error = error.toString();
      if (!_recording) _pending = null;
    } finally {
      if (mounted) setState(() => _busy = false);
      if (!_foreground && _recording) unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    if (_busy || _pending == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_recording) {
        await _recorder.stop();
        _recording = false;
        _timer?.cancel();
        _elapsed.stop();
        _pending!['ended_at'] = DateTime.now().toUtc().toIso8601String();
      }
      await _repository.saveRecording(widget.scope, _pending!, _notes.text.trim());
      _pending = null;
      _saved++;
      _notes.clear();
      await _loadSegments();
    } catch (error) {
      _error = 'Audio has not been confirmed saved: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _recorder.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _elapsed.elapsed.inSeconds;
    return PopScope(canPop: !_busy && _pending == null,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.reviewOnly ? 'Visit records' : 'Visit recording'),
          actions: [IconButton(tooltip: 'Refresh recordings',
            onPressed: _busy || _pending != null || _loadingSegments ? null : _loadSegments,
            icon: const Icon(Icons.refresh))]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(widget.supplierName, style: Theme.of(context).textTheme.headlineSmall),
          if (!widget.reviewOnly) ...[
          const SizedBox(height: 8),
          const Text('Record the supplier conversation or your own observations as separate audio notes.'),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Recording type'),
            items: const [DropdownMenuItem(value: 'conversation', child: Text('Supplier conversation')),
              DropdownMenuItem(value: 'voice_note', child: Text('Team voice note'))],
            onChanged: _busy || _pending != null ? null : (value) => setState(() {
              _kind = value!; _consent = false;
            })),
          const SizedBox(height: 16),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: _consent,
            title: Text(_kind == 'conversation'
              ? 'Participants have agreed to this recording'
              : 'I am recording my own note with permission for anyone else included'),
            onChanged: _busy || _pending != null ? null : (value) =>
              setState(() => _consent = value ?? false)),
          const SizedBox(height: 20),
          Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
            Icon(_recording ? Icons.mic : Icons.mic_none, size: 40,
              color: _recording ? Theme.of(context).colorScheme.error : null),
            const SizedBox(height: 12),
            Text('${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.headlineLarge),
            Text(_recording ? 'Recording now' : _pending != null
              ? 'Audio pending save' : 'Ready to record'),
          ]))),
          const SizedBox(height: 20),
          TextField(controller: _notes, enabled: !_busy, minLines: 3, maxLines: 6,
            decoration: const InputDecoration(labelText: 'Notes for this recording',
              hintText: 'Product, topic, or context to keep with the audio')),
          const SizedBox(height: 20),
          ],
          if (_error != null) Semantics(liveRegion: true, child: Padding(
            padding: const EdgeInsets.only(bottom: 16), child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          if (_busy) const LinearProgressIndicator(),
          if (_progress != null) Text(_progress!),
          if (!widget.reviewOnly) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _pending != null
            ? _stop : _consent ? _start : null,
            icon: Icon(_recording ? Icons.stop : _pending != null ? Icons.save : Icons.mic),
            label: Text(_recording ? 'Stop and save segment' : _pending != null
              ? 'Retry saving audio' : _saved > 0 ? 'Record another segment' : 'Start recording')),
          const SizedBox(height: 16),
          if (_saved > 0) Text('$_saved audio segment(s) saved to this supplier and linked to the visit.'),
          const SizedBox(height: 16),
          const Text('Keep this screen open. Leaving the foreground stops and saves the current segment; recording does not restart automatically. Saved audio appears in supplier files.'),
          ],
          if (_loadingSegments) const Padding(
            padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (!_loadingSegments && _segments.isEmpty && _error == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No saved recordings are available for this visit on this device. '
                'If a teammate recorded it, sync the workspace and refresh.')),
          if (_segments.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Saved recordings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: _language,
              decoration: const InputDecoration(labelText: 'Report language'),
              items: ['English', 'Chinese', 'Arabic', 'Hindi'].map((language) =>
                DropdownMenuItem(value: language, child: Text(language))).toList(),
              onChanged: _busy ? null : (value) => setState(() => _language = value!)),
            const SizedBox(height: 12),
            const Text('Optional online processing, up to 4 MB per segment. Review every transcript and report against the audio. Speaker labels are estimates.'),
            for (final row in _segments) _segmentCard(row),
          ],
          const SizedBox(height: 12),
          if (!widget.reviewOnly)
            const Text('An unexpected process termination can leave an unfinished audio file. Recovery metadata is retained locally; automatic recovery is not yet available.'),
        ]),
      ));
  }

  Widget _segmentCard(Map<String, Object?> row) {
    final note = VisitAiService.metadata(row);
    final transcript = note['transcription'];
    final analysis = note['analysis'];
    return Card(margin: const EdgeInsets.only(top: 16), child: Padding(
      padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(note['kind'] == 'voice_note' ? 'Team voice note' : 'Supplier conversation',
            style: Theme.of(context).textTheme.titleMedium),
          Text('${note['started_at'] ?? ''}'),
          TextButton.icon(
            onPressed: _busy || _pending != null ? null : () =>
              Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
                VisitAudioPlayerScreen(scope: widget.scope, path: row['path'] as String,
                  supplierName: widget.supplierName,
                  transcript: transcript is Map ? '${transcript['text'] ?? ''}' : '',
                  report: analysis is Map ? '${analysis['text'] ?? ''}' : ''))),
            icon: const Icon(Icons.headphones_outlined), label: const Text('Listen and review')),
          if (transcript is Map) ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('Original transcript'),
            children: [SelectableText('${transcript['text'] ?? ''}')]),
          if (analysis is Map) ExpansionTile(tilePadding: EdgeInsets.zero,
            title: Text('Discussion report (${analysis['language']})'),
            subtitle: const Text('AI suggestion - review required'),
            children: [SelectableText('${analysis['text'] ?? ''}')]),
          if (analysis is! Map) TextButton.icon(
            onPressed: _busy || _pending != null ? null : () => _process(row, transcript is! Map),
            icon: Icon(transcript is Map ? Icons.translate : Icons.text_snippet_outlined),
            label: Text(transcript is Map ? 'Translate and summarize' : 'Transcribe audio')),
        ])));
  }
}
