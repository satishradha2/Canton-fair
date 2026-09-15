import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../data/team_workspace_service.dart';

class VisitAudioPlayerScreen extends StatefulWidget {
  const VisitAudioPlayerScreen({super.key, required this.scope, required this.path,
    required this.supplierName, required this.transcript, required this.report});
  final String scope;
  final String path;
  final String supplierName;
  final String transcript;
  final String report;

  @override
  State<VisitAudioPlayerScreen> createState() => _VisitAudioPlayerScreenState();
}

class _VisitAudioPlayerScreenState extends State<VisitAudioPlayerScreen>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  StreamSubscription<PlayerException>? _errors;
  bool _loading = true;
  bool _commandBusy = false;
  bool _closing = false;
  bool _canPop = false;
  bool _foreground = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = _player.errorStream.listen((_) => _showError(
      'This recording could not be played. The original file is unchanged.'));
    unawaited(_load());
  }

  void _showError(String message) {
    if (mounted && !_closing) setState(() => _error = message);
  }

  Future<void> _checkScope() async {
    if (await TeamWorkspaceService().scopeKey() != widget.scope) {
      throw StateError('Workspace changed. Close this screen and reopen the visit.');
    }
  }

  Future<void> _load() async {
    try {
      await _checkScope();
      final file = File(widget.path);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('Audio is not available on this device. Sync the workspace, '
          'then reopen this recording.');
      }
      if (!mounted || _closing) return;
      await _player.setAudioSource(AudioSource.uri(Uri.file(file.path)))
        .timeout(const Duration(seconds: 20));
      await _checkScope();
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted && !_closing) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_commandBusy || _closing || !_foreground) return;
    setState(() => _commandBusy = true);
    try {
      await _checkScope();
      if (!mounted || _closing || !_foreground) return;
      if (_player.playing && _player.processingState != ProcessingState.completed) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        if (!mounted || _closing || !_foreground) return;
        // play() completes at the end of playback, not when playback starts.
        unawaited(_player.play().catchError((Object error) {
          _showError('Playback could not start. Close and reopen the recording.');
        }));
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted && !_closing) setState(() => _commandBusy = false);
    }
  }

  Future<void> _seek(double milliseconds) async {
    if (_closing || _loading) return;
    try { await _player.seek(Duration(milliseconds: milliseconds.round())); }
    catch (_) { _showError('Could not seek to that position.'); }
  }

  Future<void> _pause() async {
    try { await _player.pause(); }
    catch (_) { _showError('Playback was interrupted. Reopen the recording.'); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_pause());
  }

  Future<void> _leave() async {
    if (_closing) return;
    setState(() => _closing = true);
    try { await _player.stop(); }
    catch (_) { /* dispose releases the player even if stopping fails. */ }
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errors?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  String _time(Duration duration) =>
    '${duration.inMinutes.toString().padLeft(2, '0')}:'
    '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_leave()); },
    child: Scaffold(
      appBar: AppBar(title: const Text('Listen and review'),
        leading: IconButton(onPressed: _closing ? null : _leave,
          tooltip: 'Close playback', icon: const Icon(Icons.arrow_back))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(widget.supplierName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Listen to the original audio and check the AI suggestions below.'),
        const SizedBox(height: 24),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!_loading && _error == null) Card(child: Padding(
          padding: const EdgeInsets.all(16), child: Column(children: [
            StreamBuilder<Duration?>(stream: _player.durationStream,
              initialData: _player.duration, builder: (context, totalSnapshot) {
                final total = totalSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration>(stream: _player.positionStream,
                  initialData: _player.position, builder: (context, snapshot) {
                    final maximum = total.inMilliseconds.toDouble();
                    final position = (snapshot.data ?? Duration.zero).inMilliseconds
                      .toDouble().clamp(0.0, maximum).toDouble();
                    return Column(children: [
                      Slider(value: position, max: maximum > 0 ? maximum : 1,
                        label: _time(Duration(milliseconds: position.round())),
                        onChanged: maximum > 0 && !_closing ? _seek : null),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(_time(Duration(milliseconds: position.round()))), Text(_time(total)),
                      ]),
                    ]);
                  });
              }),
            const SizedBox(height: 12),
            StreamBuilder<PlayerState>(stream: _player.playerStateStream,
              initialData: _player.playerState, builder: (context, snapshot) {
                final playing = snapshot.data?.playing == true &&
                  snapshot.data?.processingState != ProcessingState.completed;
                return FilledButton.icon(onPressed: _commandBusy || _closing ? null : _toggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: Text(playing ? 'Pause' : 'Play'));
              }),
          ]))),
        const SizedBox(height: 24),
        if (widget.transcript.isNotEmpty) ExpansionTile(
          initiallyExpanded: true, tilePadding: EdgeInsets.zero,
          title: const Text('Original transcript'),
          children: [SelectableText(widget.transcript)]),
        if (widget.report.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero,
          title: const Text('Discussion report'),
          subtitle: const Text('AI suggestion - review required'),
          children: [SelectableText(widget.report)]),
        if (widget.transcript.isEmpty) const Text('No transcript yet. Return to the recording to request transcription.'),
        const SizedBox(height: 16),
        const Text('Playback is local. It pauses when the app leaves the foreground and does not resume automatically.'),
      ]),
    ),
  );
}
