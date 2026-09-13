import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_workspace_service.dart';

class EditLock {
  final String userId;
  final String userEmail;
  final DateTime expiresAt;

  const EditLock(this.userId, this.userEmail, this.expiresAt);
}

class EditLockService {
  final _client = Supabase.instance.client;
  final _workspace = TeamWorkspaceService();

  Future<EditLock?> acquire(String recordType, String recordId) async {
    final user = _client.auth.currentUser;
    final team = user == null ? null : await _workspace.load();
    if (user == null || team == null) return null;
    try {
      final result = await _client.rpc('acquire_edit_lock', params: {
        'target_team': team.id,
        'target_record_type': recordType,
        'target_record_id': recordId,
      });
      if (result is! List || result.isEmpty) return null;
      final row = Map<String, dynamic>.from(result.first as Map);
      return EditLock(
        row['user_id'].toString(),
        row['user_email']?.toString() ?? '',
        DateTime.parse(row['expires_at'].toString()),
      );
    } on PostgrestException {
      // The app remains usable until the optional cloud migration is applied.
      return null;
    }
  }

  Future<void> release(String recordType, String recordId) async {
    final user = _client.auth.currentUser;
    final team = user == null ? null : await _workspace.load();
    if (user == null || team == null) return;
    try {
      await _client.rpc('release_edit_lock', params: {
        'target_team': team.id,
        'target_record_type': recordType,
        'target_record_id': recordId,
      });
    } on PostgrestException {
      // Optional migration not installed yet.
    }
  }
}
