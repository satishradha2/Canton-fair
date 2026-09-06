/// Conservative OCR comparison, not a guarantee of complete transcription.
class CardCropTextCheck {
  const CardCropTextCheck._(this.complete, this.verified, this.missingLines);

  final bool complete;
  final bool verified;
  final List<String> missingLines;

  static CardCropTextCheck evaluate({
    required Map<String, dynamic> originals,
    required Map<String, dynamic> cropped,
    required Set<String> requiredScripts,
  }) {
    String normalize(String text) => text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    String combined(Map<String, dynamic> passes) => normalize(passes.values
        .map((pass) => (pass as Map)['text'] as String? ?? '').join('\n'));
    final cropText = combined(cropped);
    final sourceLines = <String>{
      for (final pass in originals.values)
        for (final line in ((pass as Map)['text'] as String? ?? '').split(RegExp(r'[\r\n]+')))
          if (normalize(line).isNotEmpty) normalize(line),
    };
    final missing = sourceLines.where((line) => !cropText.contains(line)).toList();
    final complete = requiredScripts.isNotEmpty && requiredScripts.every(
        (script) => originals.containsKey(script) && cropped.containsKey(script));
    final verified = complete && combined(originals).length >= 20 &&
        cropText.length >= 20 && missing.isEmpty;
    return CardCropTextCheck._(complete, verified, List.unmodifiable(missing));
  }
}
