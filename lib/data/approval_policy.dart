import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'team_workspace_service.dart';

class ApprovalPolicy {
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
    final row = await client.from('team_members').select('role')
        .eq('team_id', team.id).eq('user_id', user).maybeSingle();
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
      throw StateError('Only a team admin can approve or review this decision.');
    }
  }

  static Future<void> checkQuote(Map<String, Object?> old, Map<String, Object?> changes) async {
    final role = await currentRole();
    if (role == 'viewer') throw StateError('Viewers cannot change quotes.');
    final previous = old['approval_status'] ?? 'Draft';
    final next = changes['approval_status'] ?? previous;
    const statuses = ['Draft', 'Pending approval', 'Approved', 'Rejected', 'Changes requested'];
    if (!statuses.contains(next)) throw StateError('Invalid quote status.');
    final reviewChanged = ['approval_status', 'approval_comment', 'approved_by', 'approved_at']
        .any((key) => changes.containsKey(key) && changes[key] != old[key]);
    if (reviewChanged && (['Approved', 'Rejected', 'Changes requested'].contains(next) ||
        ['Approved', 'Rejected'].contains(previous)) && role != 'admin') {
      throw StateError('Only a team admin can make or change a review decision.');
    }
    final commercialChanged = changes.entries.any((entry) =>
        !['approval_status', 'approval_comment', 'approved_by', 'approved_at'].contains(entry.key) &&
        entry.value != old[entry.key]);
    if (commercialChanged && previous == 'Approved') {
      throw StateError('Create a new quote revision instead of editing an approved quote.');
    }
    if (next == 'Rejected' && (changes['approval_comment'] ?? old['approval_comment'] ?? '').toString().trim().isEmpty) {
      throw StateError('A rejection reason is required.');
    }
    if (reviewChanged) {
      final isFinal = next == 'Approved' || next == 'Rejected';
      changes['approved_by'] = isFinal
          ? (Supabase.instance.client.auth.currentUser?.email ?? '') : '';
      changes['approved_at'] = isFinal ? DateTime.now().toUtc().toIso8601String() : null;
    }
  }
}
