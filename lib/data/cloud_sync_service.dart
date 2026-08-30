import 'dart:convert';
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
      if (await _isUnchanged('trip', localId, recordId, link, payload)) {
        continue;
      }
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
            'trip', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
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
      final contentHash = _payloadHash(payload);
      final localId =
          link?['local_id'] as int? ?? await _db.insert('trips', payload);
      if (link != null) {
        await _db.update('trips', localId, payload);
      }
      await _db.saveCloudLink('trip', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }
    await _db.logAudit('Cloud trip sync',
        '$uploaded uploaded, $downloaded downloaded, $conflicts conflicts.');
    return SyncResult(uploaded, downloaded, conflicts);
  }

  Future<SyncResult> syncTeamWorkspace() async {
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
      if (await _isUnchanged('supplier', localId, recordId, link, payload)) {
        continue;
      }
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
            'supplier', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
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
      final contentHash = _payloadHash(payload);
      final tripRecordId = payload.remove('trip_record_id') as String?;
      if (tripRecordId == null) continue;
      final tripLink = await _db.getCloudLinkByRecordId('trip', tripRecordId);
      if (tripLink == null) continue;
      payload['trip_id'] = tripLink['local_id'] as int;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('exhibitors', payload);
      if (link != null) await _db.update('exhibitors', localId, payload);
      await _db.saveCloudLink('supplier', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }

    for (final contact in await _db.queryAll('contacts')) {
      final localId = contact['id'] as int;
      final supplierLink =
          await _db.getCloudLink('supplier', contact['exhibitor_id'] as int);
      if (supplierLink == null) continue;
      final link = await _db.getCloudLink('contact', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(contact)
        ..remove('id')
        ..remove('exhibitor_id')
        ..['supplier_record_id'] = supplierLink['record_id'];
      if (await _isUnchanged('contact', localId, recordId, link, payload)) {
        continue;
      }
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'contact',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'contact', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final contactRecords = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'contact');
    for (final record in contactRecords) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('contact', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final contentHash = _payloadHash(payload);
      final supplierRecordId = payload.remove('supplier_record_id') as String?;
      if (supplierRecordId == null) continue;
      final supplierLink =
          await _db.getCloudLinkByRecordId('supplier', supplierRecordId);
      if (supplierLink == null) continue;
      payload['exhibitor_id'] = supplierLink['local_id'] as int;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('contacts', payload);
      if (link != null) await _db.update('contacts', localId, payload);
      await _db.saveCloudLink('contact', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }

    for (final product in await _db.queryAll('products')) {
      final localId = product['id'] as int;
      final supplierLink =
          await _db.getCloudLink('supplier', product['exhibitor_id'] as int);
      if (supplierLink == null) continue;
      final link = await _db.getCloudLink('product', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(product)
        ..remove('id')
        ..remove('exhibitor_id')
        ..['supplier_record_id'] = supplierLink['record_id'];
      if (await _isUnchanged('product', localId, recordId, link, payload)) {
        continue;
      }
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'product',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'product', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final productRecords = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'product');
    for (final record in productRecords) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('product', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final contentHash = _payloadHash(payload);
      final supplierRecordId = payload.remove('supplier_record_id') as String?;
      if (supplierRecordId == null) continue;
      final supplierLink =
          await _db.getCloudLinkByRecordId('supplier', supplierRecordId);
      if (supplierLink == null) continue;
      payload['exhibitor_id'] = supplierLink['local_id'] as int;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('products', payload);
      if (link != null) await _db.update('products', localId, payload);
      await _db.saveCloudLink('product', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }

    await _db.logAudit('Cloud workspace sync',
        '$uploaded uploaded, $downloaded downloaded, $conflicts conflicts.');
    return SyncResult(uploaded, downloaded, conflicts);
  }

  String _newRecordId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _isUnchanged(
    String recordType,
    int localId,
    String recordId,
    Map<String, dynamic>? link,
    Map<String, dynamic> payload,
  ) async {
    if (link == null) return false;
    final contentHash = _payloadHash(payload);
    final savedHash = link['content_hash'] as String? ?? '';
    if (savedHash == contentHash) return true;

    // Older app versions did not retain content fingerprints. Treat their
    // existing cloud link as the first sync baseline to avoid false conflicts.
    if (savedHash.isEmpty) {
      await _db.saveCloudLink(
        recordType,
        localId,
        recordId,
        link['version'] as int,
        contentHash: contentHash,
      );
      return true;
    }
    return false;
  }

  String _payloadHash(Map<String, Object?> payload) =>
      jsonEncode(_canonicalize(payload));

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((left, right) =>
            left.key.toString().compareTo(right.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonicalize(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }
}
