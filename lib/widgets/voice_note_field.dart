import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/models.dart';
import '../screens/supplier_voice_note_screen.dart';

class VoiceNoteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final VoidCallback? onRecordAudio;

  const VoiceNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 1,
    this.maxLines = 3,
    this.enabled = true,
    this.onRecordAudio,
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

  void _recordOriginalAudio() {
    if (widget.onRecordAudio != null) {
      widget.onRecordAudio!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SupplierVoiceNoteScreen(contextLabel: widget.label)));
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _listening || !widget.enabled ? null : _recordOriginalAudio,
              icon: const Icon(Icons.graphic_eq_outlined),
              label: const Text('Record original audio note'),
            ),
          ),
        ],
      );
}

class VoiceNoteAction extends StatelessWidget {
  const VoiceNoteAction({super.key, required this.contextLabel, this.supplier});

  final String contextLabel;
  final Exhibitor? supplier;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SupplierVoiceNoteScreen(
                    supplier: supplier,
                    contextLabel: contextLabel,
                  ))),
          icon: const Icon(Icons.graphic_eq_outlined),
          label: const Text('Record original audio note'),
        ),
      );
}
