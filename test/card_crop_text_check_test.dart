import 'package:canton_fair_crm/data/card_crop_text_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const text = 'Example Trading Company\nAlex Example\nalex@example.com\n+1 202 555 0147';
  Map<String, dynamic> passes(String value) => {'latin': {'text': value}};
  CardCropTextCheck check(String original, String crop) => CardCropTextCheck.evaluate(
      originals: passes(original), cropped: passes(crop), requiredScripts: {'latin'});

  test('accepts a complete retained reading', () {
    expect(check(text, text).verified, isTrue);
  });
  test('accepts whitespace and capitalization differences', () {
    expect(check(text, text.toUpperCase().replaceAll(' ', '  ').replaceAll('\n', ' ')).verified, isTrue);
  });
  test('rejects a missing contact number even when company text remains', () {
    final result = check(text, 'Example Trading Company\nAlex Example\nalex@example.com');
    expect(result.verified, isFalse);
    expect(result.missingLines, contains('+12025550147'));
  });
  test('rejects blank and sparse OCR rather than approving an empty match', () {
    expect(check('', '').verified, isFalse);
    expect(check('Example', 'Example').verified, isFalse);
  });
  test('requires every selected script on both images', () {
    final result = CardCropTextCheck.evaluate(originals: passes(text), cropped: passes(text),
        requiredScripts: {'latin', 'chinese'});
    expect(result.complete, isFalse);
    expect(result.verified, isFalse);
  });
  test('rejects failed crop recognition', () {
    final result = CardCropTextCheck.evaluate(originals: passes(text), cropped: {},
        requiredScripts: {'latin'});
    expect(result.verified, isFalse);
  });
  test('protects short Chinese text as well as long Latin lines', () {
    const chinese = '\u4e2d\u56fd';
    expect(check('$text\n$chinese', text).verified, isFalse);
    expect(check('$text\n$chinese', '$text\n$chinese').verified, isTrue);
  });
  test('does not require manual edits to match OCR', () {
    // Only image readings participate; reviewed supplier fields are untouched.
    expect(check(text, '$text\nAdditional newly readable text').verified, isTrue);
  });
}
