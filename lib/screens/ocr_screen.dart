import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../data/business_card_parser.dart';
import '../data/camera_capture_service.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  bool _busy = false;
  String? _error;
  String? _recognizedText;
  static const _fields = <String, String>{
    'name': 'Company / supplier name',
    'person': 'Contact person',
    'email': 'Email',
    'phone': 'Phone',
    'wechat': 'WeChat',
    'booth': 'Booth',
    'hall': 'Hall',
    'country': 'Country',
  };
  final _controllers = <String, TextEditingController>{
    for (final key in _fields.keys) key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _useDetails() {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    if (_controllers['name']!.text.trim().isEmpty) {
      setState(() => _error = 'Enter or confirm the company / supplier name.');
      return;
    }
    Navigator.of(context).pop<Map<String, String>>({
      for (final entry in _controllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    });
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await _extractText();
      if (!mounted || text == null) return;
      if (text.trim().isEmpty) {
        setState(() => _error =
            'No text detected. Try again with a clearer card image.');
      } else {
        final suggestions = BusinessCardParser.parse(text);
        setState(() {
          _recognizedText = text;
          for (final entry in _controllers.entries) {
            entry.value.text = suggestions[entry.key] ?? '';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not read the card. Check camera permission and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _extractText() async {
    final picker = ImagePicker();
    final XFile? image = await CameraCaptureService.capture(
      () => picker.pickImage(source: ImageSource.camera),
    );
    if (image == null) return null;
    final inputImage = InputImage.fromFilePath(image.path);
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(inputImage);
      return result.text;
    } finally {
      await recognizer.close();
      try {
        final f = File(image.path);
        if (await f.exists()) await f.delete();
      } on FileSystemException catch (_) {
        // Temporary-file cleanup must not discard successfully recognized text.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Card Capture')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Waiting for the photo or reading card text...'),
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                Semantics(liveRegion: true, child: Text(_error!)),
                const SizedBox(height: 16),
              ],
              if (_recognizedText != null) ...[
                Text('Review scanned details',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  'OCR can confuse letters and digits. Check every field against '
                  'the card, especially O/Q/0. Blank fields need manual entry. '
                  'Nothing is saved until you complete supplier capture.',
                ),
                ExpansionTile(
                  title: const Text('Recognized text'),
                  children: [Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_recognizedText!),
                  )],
                ),
                for (final entry in _fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: _controllers[entry.key],
                      enabled: !_busy,
                      decoration: InputDecoration(labelText: entry.value),
                    ),
                  ),
                ElevatedButton(
                  onPressed: _busy ? null : _useDetails,
                  child: const Text('Use reviewed details'),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                onPressed: _busy ? null : _scan,
                child: Text(_recognizedText == null
                    ? 'Scan business card with camera'
                    : 'Retake photo (replaces reviewed fields)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
