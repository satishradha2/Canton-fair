import 'package:canton_fair_crm/data/field_intelligence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = FieldIntelligenceService();

  test('calculates container capacity using volume and payload limits', () {
    final result = service.containerLoad(
      cartonLengthCm: 50,
      cartonWidthCm: 40,
      cartonHeightCm: 30,
      cartonWeightKg: 12,
      unitsPerCarton: 10,
      containerCbm: 67,
      payloadKg: 26500,
    );
    expect(result['carton_cbm'], closeTo(.06, .0001));
    expect(result['recommended_cartons'], 949);
    expect(result['recommended_units'], 9490);
  });

  test('builds AQL sample guidance', () {
    expect(service.aqlSampleSize(1000), 80);
    expect(service.defectLimits(80), {'critical': 0, 'major': 2, 'minor': 3});
  });

  test('normalizes currencies through the euro reference base', () {
    final snapshot = CurrencySnapshot(
        date: DateTime(2026, 9, 1), perEuro: const {'USD': 1.2, 'CNY': 8.4});
    expect(snapshot.convert(100, 'USD', 'CNY'), closeTo(700, .001));
    expect(snapshot.convert(100, 'USD', 'USD'), 100);
  });

  test('round trips an offline transfer envelope', () {
    final encoded = service.encodeTransfer({
      'supplier': {'name': 'Acme'}
    });
    final decoded = service.decodeTransfer(encoded);
    expect((decoded['supplier'] as Map)['name'], 'Acme');
  });

  test('sorts incomplete high priority route stops first', () {
    final input = [
      {'hall': 'B', 'booth': '20', 'priority': 1, 'done': false},
      {'hall': 'A', 'booth': '2', 'priority': 5, 'done': false},
      {'hall': 'A', 'booth': '1', 'priority': 9, 'done': true},
    ];
    final result = service.reorderRoute(input,
        hall: (item) => item['hall'] as String,
        booth: (item) => item['booth'] as String,
        priority: (item) => item['priority'] as int,
        completed: (item) => item['done'] as bool);
    expect(result.first['booth'], '2');
    expect(result.last['done'], true);
  });
}
