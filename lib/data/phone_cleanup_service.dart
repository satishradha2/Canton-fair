import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'approval_policy.dart';
import 'phone_cleanup_plan.dart';
import 'team_workspace_service.dart';

/// Only the approval and audit tables are written. Never deletes cloud records.
class PhoneCleanupService {
  final _client = Supabase.instance.client;
  final _workspace = TeamWorkspaceService();
  static const _storage = FlutterSecureStorage();

  static Future<String> deviceId() async {
    const key = 'phone_cleanup_installation_id_v1';
    final saved = await _storage.read(key: key);
    if (saved != null) return saved;
    final random = Random.secure();
    final id = List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: key, value: id);
    return id;
  }

  static Future<bool> paused(String scope) async =>
    await _storage.read(key: 'phone_cache_paused_$scope') == 'true';
  static Future<void> setPaused(String scope, bool value) =>
    _storage.write(key: 'phone_cache_paused_$scope', value: value.toString());

  Future<List<Map<String, dynamic>>> requests({bool admin = false}) async {
    final team = await _workspace.load();
    if (team == null) return [];
    if (admin) await ApprovalPolicy.requireAdmin();
    final rows = await _client.from('phone_cleanup_requests').select()
      .eq('team_id', team.id).order('created_at', ascending: false).limit(100);
    final user = _client.auth.currentUser?.id;
    final device = await deviceId();
    return [for (final row in rows)
      if (admin || (row['requested_by'] == user && row['device_id'] == device))
        Map<String, dynamic>.from(row)];
  }

  Future<String> request(PhoneCleanupPlan plan, String reason) async {
    if (reason.trim().isEmpty) throw StateError('Explain why the unsynced phone data should be cleared.');
    if (plan.scope != await _workspace.scopeKey()) throw StateError('Workspace changed. Check the phone again.');
    final result = await _client.rpc('request_phone_cleanup', params: {
      'target_team': plan.teamId, 'target_device': await deviceId(),
      'snapshot_hash': plan.manifestHash, 'summary': plan.summary, 'request_reason': reason.trim(),
    });
    return result as String;
  }

  Future<void> decide(String id, bool approve, String note) async {
    await ApprovalPolicy.requireAdmin();
    await _client.rpc('review_phone_cleanup', params: {
      'request_id': id, 'approve': approve, 'review_note': note.trim(),
    });
  }

  Future<String> begin(PhoneCleanupPlan plan, {String? approvalId}) async {
    return await _client.rpc('begin_phone_cleanup', params: {
      'target_team': plan.teamId, 'target_device': await deviceId(),
      'snapshot_hash': plan.manifestHash, 'summary': plan.summary,
      'approval_id': approvalId,
    }) as String;
  }

  Future<void> complete(String eventId, int records, int files, List<String> warnings) async {
    await _client.rpc('complete_phone_cleanup', params: {
      'event_id': eventId, 'result': {'records_removed': records, 'files_removed': files, 'warnings': warnings},
    });
  }
}
