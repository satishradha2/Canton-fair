import 'package:flutter_test/flutter_test.dart';
import 'package:canton_fair_crm/data/legacy_participation_reconciliation.dart';

void main() {
  const link = <String, dynamic>{'version': 0, 'content_hash': ''};
  const local = <String, Object?>{
    'supplier_record_id': 'supplier-a', 'trip_record_id': 'trip-a',
    'source': 'legacy', 'organizer_id': null, 'created_at': '2026-09-15',
  };
  const remote = <String, Object?>{
    'supplier_record_id': 'supplier-a', 'trip_record_id': 'trip-a',
    'source': 'manual', 'organizer_id': 'organizer-a',
    'created_at': '2026-09-14',
  };

  test('adopts existing participation despite generated timestamp and source', () {
    expect(isLegacyParticipationSeed(link, local, remote), isTrue);
  });
  test('never reconciles a previously synced or baselined record', () {
    expect(isLegacyParticipationSeed({...link, 'version': 1}, local, remote), isFalse);
    expect(isLegacyParticipationSeed({...link, 'content_hash': 'baseline'}, local, remote), isFalse);
  });
  test('preserves user-entered source, organizer, and additional fields', () {
    for (final edit in <Map<String, Object?>>[
      {'source': 'manual'}, {'organizer_id': 'changed'}, {'notes': 'Keep me'},
      {'_deleted': true},
    ]) {
      expect(isLegacyParticipationSeed(link, {...local, ...edit}, remote), isFalse);
    }
  });
  test('requires matching nonempty cloud parent identities', () {
    for (final key in ['supplier_record_id', 'trip_record_id']) {
      for (final value in [null, '', 'different']) {
        expect(isLegacyParticipationSeed(link, {...local, key: value}, remote), isFalse);
      }
      expect(isLegacyParticipationSeed(link, local, {...remote, key: 'different'}), isFalse);
    }
  });
  test('does not adopt deleted or invalid remote records', () {
    for (final deleted in [true, 'true']) {
      expect(isLegacyParticipationSeed(link, local, {...remote, '_deleted': deleted}), isFalse);
    }
    expect(isLegacyParticipationSeed(link, local, null), isFalse);
    expect(isLegacyParticipationSeed(link, local, 'invalid'), isFalse);
  });
}
