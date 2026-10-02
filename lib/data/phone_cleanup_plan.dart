class PhoneCleanupEntry {
  const PhoneCleanupEntry({required this.type, required this.id,
    required this.row, required this.parents, required this.cloudVerified});
  final String type;
  final int id;
  final Map<String, Object?> row;
  final Set<String> parents;
  final bool cloudVerified;
  String get key => '$type:$id';
}

class PhoneCleanupPlan {
  const PhoneCleanupPlan({required this.scope, required this.teamId,
    required this.manifestHash, required this.snapshot, required this.entries,
    required this.files, required this.clearable, required this.localOnlyCount});
  final String scope, teamId, manifestHash;
  final Map<String, Object?> snapshot;
  final List<PhoneCleanupEntry> entries;
  /// Absolute app-private paths and their current checksums.
  final Map<String, String> files;
  final Set<String> clearable;
  final int localOnlyCount;
  int get verifiedCount => clearable.length;
  int get protectedCount => entries.length - clearable.length;
  Map<String, Object?> get summary => {
    'saved_records': entries.length, 'cloud_verified_clearable': verifiedCount,
    'protected_records': protectedCount, 'local_only_items': localOnlyCount,
    'files': files.length,
    'by_type': {for (final type in entries.map((entry) => entry.type).toSet())
      type: entries.where((entry) => entry.type == type).length},
  };
}
