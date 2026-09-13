import 'dart:io';

import 'package:image/image.dart' as img;

class SimilarPhoto {
  final int attachmentId;
  final String path;
  final String supplierName;
  final double similarity;

  const SimilarPhoto({
    required this.attachmentId,
    required this.path,
    required this.supplierName,
    required this.similarity,
  });
}

class PhotoSimilarityService {
  Future<int?> hashFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final source = img.decodeImage(await file.readAsBytes());
    if (source == null) return null;
    final small = img.copyResize(source, width: 8, height: 8);
    final values = <double>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final pixel = small.getPixel(x, y);
        values.add((pixel.r + pixel.g + pixel.b) / 3);
      }
    }
    final average = values.reduce((a, b) => a + b) / values.length;
    var hash = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] >= average) hash |= 1 << i;
    }
    return hash;
  }

  double compare(int first, int second) {
    var different = 0;
    var value = first ^ second;
    while (value != 0) {
      different += value & 1;
      value >>= 1;
    }
    return 1 - different / 64;
  }
}
