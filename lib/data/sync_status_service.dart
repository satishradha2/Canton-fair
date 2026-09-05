import 'dart:convert';
import 'team_workspace_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SyncStatus {
  final DateTime? lastSyncedAt;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final String? lastError;

  const SyncStatus({
    this.lastSyncedAt,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.lastError,
  });

  factory SyncStatus.fromJson(Map<String, dynamic> json) => SyncStatus(
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.tryParse(json['last_synced_at'] as String),
        uploaded: json['uploaded'] as int? ?? 0,
        downloaded: json['downloaded'] as int? ?? 0,
        conflicts: json['conflicts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
      );
}

class SyncStatusService {
  static const _key = 'cloud_sync_status';
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static final ValueNotifier<bool> isSyncing = ValueNotifier(false);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static void setSyncing(bool value) {
    if (isSyncing.value == value) return;
    isSyncing.value = value;
    changes.value++;
  }

  Future<SyncStatus> load() async {
    final value = await _storage.read(key: '${_key}_${await TeamWorkspaceService().scopeKey()}');
    if (value == null) return const SyncStatus();
    try {
      return SyncStatus.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return const SyncStatus();
    }
  }

  Future<void> recordSuccess({
    required int uploaded,
    required int downloaded,
    required int conflicts,
  }) =>
      _save({
        'last_synced_at': DateTime.now().toIso8601String(),
        'uploaded': uploaded,
        'downloaded': downloaded,
        'conflicts': conflicts,
        'last_error': null,
      });

  Future<void> recordFailure(Object error) async {
    final previous = await load();
    await _save({
      'last_synced_at': previous.lastSyncedAt?.toIso8601String(),
      'uploaded': previous.uploaded,
      'downloaded': previous.downloaded,
      'conflicts': previous.conflicts,
      'last_error': error.toString(),
    });
  }

  Future<void> _save(Map<String, Object?> value) async {
    await _storage.write(key: '${_key}_${await TeamWorkspaceService().scopeKey()}', value: jsonEncode(value));
    changes.value++;
  }
}
