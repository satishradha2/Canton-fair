import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceNoteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;

  const VoiceNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 3,
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
        if (mounted)
          setState(() {
            _listening = false;
            _error = error.errorMsg;
          });
      },
    );
    if (!available) {
      if (mounted)
        setState(
            () => _error = 'Speech recognition is unavailable on this device.');
      return;
    }
    if (mounted)
      setState(() {
        _listening = true;
        _error = '';
      });
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
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 5),
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
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              labelText: widget.label,
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: _listening ? 'Stop voice capture' : 'Speak note',
                onPressed: _toggleListening,
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
        ],
      );
}
