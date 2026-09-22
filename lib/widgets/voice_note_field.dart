import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../data/database.dart';
import '../models/models.dart';
import '../screens/supplier_voice_note_screen.dart';

class VoiceNoteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final VoidCallback? onRecordAudio;
  final Exhibitor? audioSupplier;
  final String? audioContext;

  const VoiceNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 1,
    this.maxLines = 3,
    this.enabled = true,
    this.onRecordAudio,
    this.audioSupplier,
    this.audioContext,
  });

  @override
  State<VoiceNoteField> createState() => _VoiceNoteFieldState();
}

class _VoiceNoteFieldState extends State<VoiceNoteField> {
  final _speech = stt.SpeechToText();
  bool _listening = false;
  String _error = '';

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = error.errorMsg;
          });
        }
      },
    );
    if (!available) {
      if (mounted) {
        setState(
            () => _error = 'Speech recognition is unavailable on this device.');
      }
      return;
    }
    if (mounted) {
      setState(() {
        _listening = true;
        _error = '';
      });
    }
    await _speech.listen(
      onResult: (result) {
        final recognized = result.recognizedWords.trim();
        if (recognized.isEmpty) return;
        final current = widget.controller.text.trim();
        widget.controller.value = TextEditingValue(
          text: current.isEmpty ? recognized : '$current $recognized',
          selection: TextSelection.collapsed(
              offset: current.isEmpty
                  ? recognized.length
                  : current.length + recognized.length + 1),
        );
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: widget.controller,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: widget.label,
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: _listening ? 'Stop voice capture' : 'Speak note',
                onPressed: widget.enabled ? _toggleListening : null,
                icon: Icon(_listening
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none_outlined),
              ),
            ),
          ),
          if (_listening)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Listening. Tap the stop button when finished.'),
            ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          VoiceNoteAction(
            contextLabel: widget.audioContext ?? widget.label,
            supplier: widget.audioSupplier,
            enabled: widget.enabled && !_listening,
          ),
        ],
      );
}

class VoiceNoteAction extends StatefulWidget {
  const VoiceNoteAction({super.key, required this.contextLabel, this.supplier, this.enabled = true});

  final String contextLabel;
  final Exhibitor? supplier;
  final bool enabled;

  @override
  State<VoiceNoteAction> createState() => _VoiceNoteActionState();
}

class _VoiceNoteActionState extends State<VoiceNoteAction> {
  Exhibitor? _supplier;
  Future<List<Attachment>>? _recordings;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _refresh();
  }

  void _refresh() {
    if (_supplier?.id == null) return;
    _recordings = TradeDatabase.instance
        .getAttachments('exhibitor', _supplier!.id!)
        .then((items) => items.where(_matchesContext).toList());
  }

  bool _matchesContext(Attachment attachment) {
    if (attachment.kind != 'audio') return false;
    try {
      final metadata = jsonDecode(attachment.note);
      return metadata is Map && metadata['context'] == widget.contextLabel;
    } catch (_) {
      return false;
    }
  }

  String _summary(Attachment attachment) {
    try {
      final metadata = jsonDecode(attachment.note);
      if (metadata is Map) {
        return [metadata['recorded_at'], metadata['notes']]
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .join(' · ');
      }
    } catch (_) {
      // Keep the attachment visible if legacy metadata is incomplete.
    }
    return 'Saved audio note';
  }

  Future<void> _openRecorder() async {
    final supplier = await Navigator.of(context).push<Exhibitor>(MaterialPageRoute(
        builder: (_) => SupplierVoiceNoteScreen(
              supplier: _supplier,
              contextLabel: widget.contextLabel,
            )));
    if (!mounted || supplier?.id == null) return;
    setState(() {
      _supplier = supplier;
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: widget.enabled ? _openRecorder : null,
            icon: const Icon(Icons.graphic_eq_outlined),
            label: const Text('Record original audio note'),
          ),
          if (_recordings != null)
            FutureBuilder<List<Attachment>>(
              future: _recordings,
              builder: (context, snapshot) {
                final recordings = snapshot.data ?? const <Attachment>[];
                if (recordings.isEmpty) return const SizedBox.shrink();
                return Column(children: [
                  for (final recording in recordings)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.graphic_eq_outlined),
                        title: Text('Audio note · ${_supplier?.name ?? 'Supplier'}'),
                        subtitle: Text(_summary(recording),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: widget.enabled ? _openRecorder : null,
                      ),
                    ),
                ]);
              },
            ),
        ],
      );
}
