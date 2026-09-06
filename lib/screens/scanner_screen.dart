import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _resultReturned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR / Barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_resultReturned || !mounted ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final first = barcodes.first;
          final value = first.rawValue;
          if (value != null && value.isNotEmpty) {
            _resultReturned = true;
            Navigator.of(context).pop<String>(value);
          }
        },
      ),
    );
  }
}
