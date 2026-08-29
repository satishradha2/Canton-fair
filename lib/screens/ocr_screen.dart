import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrScreen extends StatelessWidget {
  const OcrScreen({super.key});

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
      recognizer.close();
      final f = File(image.path);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Card Capture')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final text = await _extractText();
            if (!context.mounted) return;
            if (text == null || text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No text detected, try again with clearer card image.')),
              );
              return;
            }
            Navigator.of(context).pop<String>(text);
          },
          child: const Text('Scan business card with camera'),
        ),
      ),
    );
  }
}

