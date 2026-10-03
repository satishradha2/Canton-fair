import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'team_workspace_service.dart';
import 'database.dart';
import 'field_work_sync_contract.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApprovalPolicy {
  static Future<bool> canEditRecord(String table, int id) async {
    final workspace = TeamWorkspaceService();
    final team = await workspace.load();
    final role = await currentRole();
    if (role == 'admin') return true;
    if (role != 'member') return false;
    if (team == null) return true;
    final types = {...TradeDatabase.syncTables, ...FieldWorkSyncContract.tables};
    final matches = types.entries.where((entry) => entry.value == table);
    if (matches.isEmpty) return false;
    final type = matches.first.key;
    final db = await TradeDatabase.instance.database;
    final links = await db.query('cloud_links', where: 'record_type=? AND local_id=?', whereArgs: [type, id]);
    // Local databases are isolated by user and team. Unuploaded rows belong to this user.
    if (links.isEmpty || links.first['version'] == 0) return true;
    final recordId = links.first['record_id'] as String;
    final client = Supabase.instance.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) return false;
    final scope = await workspace.scopeKey();
    const storage = FlutterSecureStorage();
    final key = 'record_owner_${scope}_${type}_$recordId';
    // Never infer original ownership from the last editor.
    final row = await client.from('team_records').select('created_by')
        .eq('team_id', team.id).eq('record_type', type).eq('record_id', recordId).maybeSingle();
    final owner = row?['created_by'] as String?;
    await storage.write(key: key, value: owner ?? 'unknown');
    if (scope != await workspace.scopeKey()) return false;
    return owner == actor;
  }

  static Future<void> requireRecordEditor(String table, int id) async {
    if (!await canEditRecord(table, id)) {
      throw StateError('View only: only the creator or a workspace administrator can edit this record.');
    }
  }

  static Map<String, dynamic> jsonObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.isEmpty) return {};
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('Expected a JSON object.');
    return Map<String, dynamic>.from(decoded);
  }

  static Future<String> currentRole() async {
    final workspace = TeamWorkspaceService();
    final team = await workspace.load();
    if (team == null) return 'admin'; // Owner of private local records.
    final client = Supabase.instance.client;
    final user = client.auth.currentUser?.id;
    if (user == null) throw StateError('Sign in before reviewing records.');
    final row = await client
        .from('team_members')
        .select('role')
        .eq('team_id', team.id)
        .eq('user_id', user)
        .maybeSingle();
    if (row == null) throw StateError('Team membership is required.');
    return row['role'] as String;
  }

  static Future<void> requireWriter() async {
    if (!['admin', 'member'].contains(await currentRole())) {
      throw StateError('This team is read-only for your account.');
    }
  }

  static Future<void> requireAdmin() async {
    if (await currentRole() != 'admin') {
      throw StateError(
          'Only a team admin can approve or review this decision.');
    }
  }

  static Future<void> checkQuote(
      Map<String, Object?> old, Map<String, Object?> changes) async {
    final role = await currentRole();
    if (role == 'viewer') throw StateError('Viewers cannot change quotes.');
    final previous = old['approval_status'] ?? 'Draft';
    final next = changes['approval_status'] ?? previous;
    const statuses = [
      'Draft',
      'Pending approval',
      'Approved',
      'Rejected',
      'Changes requested'
    ];
    if (!statuses.contains(next)) throw StateError('Invalid quote status.');
    final reviewChanged = [
      'approval_status',
      'approval_comment',
      'approved_by',
      'approved_at'
    ].any((key) => changes.containsKey(key) && changes[key] != old[key]);
    if (reviewChanged &&
        (['Approved', 'Rejected', 'Changes requested'].contains(next) ||
            ['Approved', 'Rejected'].contains(previous)) &&
        role != 'admin') {
      throw StateError(
          'Only a team admin can make or change a review decision.');
    }
    final commercialChanged = changes.entries.any((entry) =>
        !['approval_status', 'approval_comment', 'approved_by', 'approved_at']
            .contains(entry.key) &&
        entry.value != old[entry.key]);
    if (commercialChanged && previous == 'Approved') {
      throw StateError(
          'Create a new quote revision instead of editing an approved quote.');
    }
    if (next == 'Rejected' &&
        (changes['approval_comment'] ?? old['approval_comment'] ?? '')
            .toString()
            .trim()
            .isEmpty) {
      throw StateError('A rejection reason is required.');
    }
    if (reviewChanged) {
      final isFinal = next == 'Approved' || next == 'Rejected';
      changes['approved_by'] = isFinal
          ? (Supabase.instance.client.auth.currentUser?.email ?? '')
          : '';
      changes['approved_at'] =
          isFinal ? DateTime.now().toUtc().toIso8601String() : null;
    }
  }
}
