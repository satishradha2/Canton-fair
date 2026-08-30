import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class SyncResult {
  final int uploaded;
  final int downloaded;
  final int conflicts;
  const SyncResult(this.uploaded, this.downloaded, this.conflicts);
}

class CloudSyncService {
  final _db = TradeDatabase.instance;
  final _workspace = TeamWorkspaceService();

  SupabaseClient get _client => Supabase.instance.client;

  Future<SyncResult> syncTrips() async {
    final team = await _workspace.load();
    if (team == null) throw StateError('Choose a cloud team before syncing.');
    var uploaded = 0;
    var conflicts = 0;
    for (final trip in await _db.queryAll('trips')) {
      final localId = trip['id'] as int;
      final link = await _db.getCloudLink('trip', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(trip)..remove('id');
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'trip',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'trip', localId, recordId, row['version'] as int);
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    var downloaded = 0;
    final records = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'trip');
    for (final record in records) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('trip', recordId);
      if (link != null && (link['version'] as int) >= version) {
        continue;
      }
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final localId =
          link?['local_id'] as int? ?? await _db.insert('trips', payload);
      if (link != null) {
        await _db.update('trips', localId, payload);
      }
      await _db.saveCloudLink('trip', localId, recordId, version);
      downloaded++;
    }
    await _db.logAudit('Cloud trip sync',
        '$uploaded uploaded, $downloaded downloaded, $conflicts conflicts.');
    return SyncResult(uploaded, downloaded, conflicts);
  }

  Future<SyncResult> syncTripsAndSuppliers() async {
    final tripResult = await syncTrips();
    final team = await _workspace.load();
    if (team == null) throw StateError('Choose a cloud team before syncing.');
    var uploaded = tripResult.uploaded;
    var downloaded = tripResult.downloaded;
    var conflicts = tripResult.conflicts;

    for (final supplier in await _db.queryAll('exhibitors')) {
      final localId = supplier['id'] as int;
      final tripLink =
          await _db.getCloudLink('trip', supplier['trip_id'] as int);
      if (tripLink == null) continue;
      final link = await _db.getCloudLink('supplier', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(supplier)
        ..remove('id')
        ..remove('trip_id')
        ..['trip_record_id'] = tripLink['record_id'];
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'supplier',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'supplier', localId, recordId, row['version'] as int);
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final records = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'supplier');
    for (final record in records) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('supplier', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final tripRecordId = payload.remove('trip_record_id') as String?;
      if (tripRecordId == null) continue;
      final tripLink = await _db.getCloudLinkByRecordId('trip', tripRecordId);
      if (tripLink == null) continue;
      payload['trip_id'] = tripLink['local_id'] as int;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('exhibitors', payload);
      if (link != null) await _db.update('exhibitors', localId, payload);
      await _db.saveCloudLink('supplier', localId, recordId, version);
      downloaded++;
    }
    await _db.logAudit('Cloud supplier sync',
        '$uploaded uploaded, $downloaded downloaded, $conflicts conflicts.');
    return SyncResult(uploaded, downloaded, conflicts);
  }

  String _newRecordId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
