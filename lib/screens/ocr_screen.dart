import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  bool _busy = false;
  String? _error;

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
      } else if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop<String>(text);
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
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
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
              ElevatedButton(
                onPressed: _busy ? null : _scan,
                child: const Text('Scan business card with camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
