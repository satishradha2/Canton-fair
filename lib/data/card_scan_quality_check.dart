import 'dart:io';

import 'package:image/image.dart' as image;

/// A conservative on-device quality signal for business-card images.
/// It raises a retake warning; it never discards a supplier's original image.
class CardScanQualityCheck {
  const CardScanQualityCheck._(this.edgeDetail, this.glareRatio, this.warnings);

  final double edgeDetail;
  final double glareRatio;
  final List<String> warnings;

  static Future<CardScanQualityCheck> evaluate(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final source = image.decodeImage(bytes);
    if (source == null) {
      return const CardScanQualityCheck._(0, 0,
          ['Image quality could not be checked. Confirm focus, lighting, and all card edges manually.']);
    }
    final sample = source.width > 720
        ? image.copyResize(source, width: 720)
        : source;
    if (sample.width < 160 || sample.height < 100) {
      return const CardScanQualityCheck._(0, 0,
          ['Card image is too small to verify. Retake it closer and keep all four edges visible.']);
    }

    var detailTotal = 0.0;
    var detailCount = 0;
    var glarePixels = 0;
    var pixels = 0;
    int luminance(image.Pixel pixel) =>
        ((pixel.r * 299 + pixel.g * 587 + pixel.b * 114) / 1000).round();
    for (var y = 1; y < sample.height - 1; y += 2) {
      for (var x = 1; x < sample.width - 1; x += 2) {
        final center = luminance(sample.getPixel(x, y));
        final horizontal = luminance(sample.getPixel(x + 1, y));
        final vertical = luminance(sample.getPixel(x, y + 1));
        detailTotal += (center - horizontal).abs() + (center - vertical).abs();
        detailCount++;
        final pixel = sample.getPixel(x, y);
        final max = [pixel.r, pixel.g, pixel.b].reduce((a, b) => a > b ? a : b);
        final min = [pixel.r, pixel.g, pixel.b].reduce((a, b) => a < b ? a : b);
        if (center >= 248 && max - min <= 28) glarePixels++;
        pixels++;
      }
    }
    final detail = detailCount == 0 ? 0.0 : detailTotal / detailCount;
    final glare = pixels == 0 ? 0.0 : glarePixels / pixels;
    final warnings = <String>[];
    if (detail < 13) {
      warnings.add('Possible blur detected. Retake the card with steady focus before saving.');
    }
    if (glare > .16) {
      warnings.add('Possible glare detected. Move the card away from direct light and retake it before saving.');
    }
    final ratio = sample.width / sample.height;
    if (ratio < .9 || ratio > 3.2) {
      warnings.add('Card framing looks unusual. Check that all four business-card edges are visible before saving.');
    }
    return CardScanQualityCheck._(detail, glare, List.unmodifiable(warnings));
  }
}
