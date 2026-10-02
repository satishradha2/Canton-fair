import 'package:flutter_test/flutter_test.dart';
import 'package:canton_fair_crm/data/product_ai_service.dart';
import 'package:canton_fair_crm/data/product_capture_service.dart';

void main() {
  test('AI review preserves manually entered values unless explicitly accepted', () {
    final current = {'name': 'Reviewed product', 'moq': '500', 'price_currency': 'USD'};
    final result = ProductAiService.applyReviewed(current,
        {'name': 'Suggested product', 'moq': '1000', 'specs': 'Steel', 'price_currency': 'CNY'}, {'specs'});
    expect(result['name'], 'Reviewed product');
    expect(result['moq'], '500');
    expect(result['price_currency'], 'USD');
    expect(result['specs'], 'Steel');
    expect(current.containsKey('specs'), false);
  });

  test('AI replaces a value only after the user accepts that field', () {
    expect(ProductAiService.applyReviewed({'moq': '500'}, {'moq': '1000'}, {'moq'})['moq'], '1000');
  });

  test('Changing a quotation appends history without overwriting the earlier quote', () {
    final original = <dynamic>[{'price': 1.5, 'currency': 'USD', 'moq': 500,
      'fair_name': 'Fair A', 'recorded_at': '2026-01-01', 'recorded_by': 'one@example.com'}];
    final next = ProductCaptureService.quotationHistory(original,
      {'price': 1.2, 'currency': 'USD', 'moq': 1000, 'fair_name': 'Fair B'}, '2026-02-01', 'two@example.com');
    expect(next.length, 2);
    expect((next.first as Map)['price'], 1.5);
    expect((next.last as Map)['price'], 1.2);
    expect((next.last as Map)['recorded_by'], 'two@example.com');
    expect(original.length, 1);
  });

  test('Saving unchanged commercial details does not duplicate quotation history', () {
    final previous = <dynamic>[{'price': 2.0, 'currency': 'USD', 'moq': 100,
      'recorded_at': '2026-01-01', 'recorded_by': 'one@example.com'}];
    expect(ProductCaptureService.quotationHistory(previous,
      {'price': 2.0, 'currency': 'USD', 'moq': 100}, '2026-02-01', 'two@example.com').length, 1);
    expect((previous.first as Map)['recorded_at'], '2026-01-01');
  });

  test('Missing price does not create a fabricated quotation', () {
    expect(ProductCaptureService.quotationHistory([], {'price': null, 'currency': 'USD'}, 'now', 'member'), isEmpty);
  });
}
