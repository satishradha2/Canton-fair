import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/database.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';

class SupplierVoiceNoteScreen extends StatefulWidget {
  const SupplierVoiceNoteScreen({super.key, this.supplier, this.contextLabel = 'Field note'});

  final Exhibitor? supplier;
  final String contextLabel;

  @override
  State<SupplierVoiceNoteScreen> createState() => _SupplierVoiceNoteScreenState();
}

class _SupplierVoiceNoteScreenState extends State<SupplierVoiceNoteScreen>
    with WidgetsBindingObserver {
  final _db = TradeDatabase.instance;
  final _recorder = AudioRecorder();
  final _note = TextEditingController();
  final Future<List<Exhibitor>> _suppliers =
      TradeDatabase.instance.getExhibitors(null);
  Exhibitor? _supplier;
  String? _path;
  bool _consent = false;
  bool _recording = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supplier = widget.supplier;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) {
      _stopAndSave();
    }
  }

  Future<void> _start() async {
    if (_supplier == null || !_consent || _saving) return;
    setState(() => _saving = true);
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission is required to record a voice note.');
      }
      final root = await getApplicationDocumentsDirectory();
      final scope = await TeamWorkspaceService().scopeKey();
      final folder = Directory('${root.path}/attachments/$scope/supplier_voice_notes');
      await folder.create(recursive: true);
      final path = '${folder.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (mounted) {
        setState(() {
          _path = path;
          _recording = true;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopAndSave() async {
    if (_saving || _path == null || _supplier?.id == null) return;
    setState(() => _saving = true);
    try {
      final result = await _recorder.stop();
      final path = result ?? _path!;
      final audio = File(path);
      if (!await audio.exists() || await audio.length() == 0) {
        throw StateError('The audio note was not saved. Please record it again.');
      }
      await _db.insert('attachments', {
        'owner_type': 'exhibitor',
        'owner_id': _supplier!.id!,
        'kind': 'audio',
        'path': path,
        'note': jsonEncode({
          'format': 'canton-supplier-audio-v1',
          'kind': 'voice_note',
          'context': widget.contextLabel,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
          'notes': _note.text.trim(),
          'consent_confirmed': true,
        }),
      });
      if (!mounted) return;
      setState(() {
        _recording = false;
        _path = null;
        _note.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Original audio note saved with this supplier.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recorder.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record voice note')),
        body: FutureBuilder<List<Exhibitor>>(
          future: _suppliers,
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Capture a clear original audio note',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Use this for supplier statements, product observations, and factory evidence. The recording is saved with the supplier for later review.'),
              const SizedBox(height: 22),
              DropdownButtonFormField<Exhibitor>(
                initialValue: _supplier,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: (snapshot.data ?? const <Exhibitor>[])
                    .where((item) => item.id != null)
                    .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _recording || _saving
                    ? null
                    : (value) => setState(() => _supplier = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Audio note label or context',
                  hintText: 'Example: Packaging discussion and production line 2',
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                title: const Text('I have permission to record anyone included in this note'),
                onChanged: _recording || _saving
                    ? null
                    : (value) => setState(() => _consent = value ?? false),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(_recording ? Icons.mic : Icons.mic_none_outlined,
                        size: 42,
                        color: _recording ? Theme.of(context).colorScheme.error : null),
                    const SizedBox(height: 12),
                    Text(_recording ? 'Recording original audio' : 'Ready to record',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('For better clarity, hold the phone close, face away from crowd noise, and record short topic-specific segments.', textAlign: TextAlign.center),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : (_recording ? _stopAndSave : _start),
                icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic),
                label: Text(_recording ? 'Stop and save audio note' : 'Start audio note'),
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ),
      );
}
