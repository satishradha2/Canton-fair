/// Recognizes only unsynced upgrade seeds, never user-entered participations.
bool isLegacyParticipationSeed(Map<String, dynamic> link,
    Map<String, Object?> local, Object? remoteValue) {
  if (link['version'] != 0 || link['content_hash'] != '' ||
      local['source'] != 'legacy' || local['organizer_id'] != null ||
      remoteValue is! Map) {
    return false;
  }
  const seedKeys = {
    'supplier_record_id', 'trip_record_id', 'source',
    'organizer_id', 'created_at',
  };
  if (local.keys.any((key) => !seedKeys.contains(key)) ||
      remoteValue['_deleted'] == true || remoteValue['_deleted'] == 'true') {
    return false;
  }
  for (final key in ['supplier_record_id', 'trip_record_id']) {
    final parent = local[key];
    if (parent is! String || parent.isEmpty || remoteValue[key] != parent) {
      return false;
    }
  }
  return true;
}
