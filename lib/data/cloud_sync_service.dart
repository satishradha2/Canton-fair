import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class SyncResult {
  final int uploaded;
  final int downloaded;
  final int conflicts;
  const SyncResult(this.uploaded, this.downloaded, this.conflicts);
}

class CloudConflict {
  final int id;
  final String teamId;
  final String recordType;
  final int localId;
  final String recordId;
  final Map<String, Object?> localPayload;
  final Map<String, Object?> remotePayload;
  final int remoteVersion;
  final DateTime createdAt;

  const CloudConflict({
    required this.id,
    required this.teamId,
    required this.recordType,
    required this.localId,
    required this.recordId,
    required this.localPayload,
    required this.remotePayload,
    required this.remoteVersion,
    required this.createdAt,
  });

  factory CloudConflict.fromMap(Map<String, dynamic> map) => CloudConflict(
        id: map['id'] as int,
        teamId: map['team_id'] as String,
        recordType: map['record_type'] as String,
        localId: map['local_id'] as int,
        recordId: map['record_id'] as String,
        localPayload: Map<String, Object?>.from(
            jsonDecode(map['local_payload'] as String) as Map),
        remotePayload: Map<String, Object?>.from(
            jsonDecode(map['remote_payload'] as String) as Map),
        remoteVersion: map['remote_version'] as int,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
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
          await _captureConflict(team.id, 'trip', localId, recordId, payload);
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
          await _captureConflict(
              team.id, 'supplier', localId, recordId, payload);
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
          await _captureConflict(
              team.id, 'contact', localId, recordId, payload);
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
          await _captureConflict(
              team.id, 'product', localId, recordId, payload);
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

    for (final meeting in await _db.queryAll('meetings')) {
      final localId = meeting['id'] as int;
      final supplierLink =
          await _db.getCloudLink('supplier', meeting['exhibitor_id'] as int);
      if (supplierLink == null) continue;
      final productId = meeting['product_id'] as int?;
      final productLink = productId == null
          ? null
          : await _db.getCloudLink('product', productId);
      if (productId != null && productLink == null) continue;
      final link = await _db.getCloudLink('meeting', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(meeting)
        ..remove('id')
        ..remove('exhibitor_id')
        ..remove('product_id')
        ..['supplier_record_id'] = supplierLink['record_id']
        ..['product_record_id'] = productLink?['record_id'];
      if (await _isUnchanged('meeting', localId, recordId, link, payload)) {
        continue;
      }
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'meeting',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'meeting', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          await _captureConflict(
              team.id, 'meeting', localId, recordId, payload);
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final meetingRecords = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'meeting');
    for (final record in meetingRecords) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('meeting', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final contentHash = _payloadHash(payload);
      final supplierRecordId = payload.remove('supplier_record_id') as String?;
      final productRecordId = payload.remove('product_record_id') as String?;
      if (supplierRecordId == null) continue;
      final supplierLink =
          await _db.getCloudLinkByRecordId('supplier', supplierRecordId);
      if (supplierLink == null) continue;
      int? productLocalId;
      if (productRecordId != null) {
        final productLink =
            await _db.getCloudLinkByRecordId('product', productRecordId);
        if (productLink == null) continue;
        productLocalId = productLink['local_id'] as int;
      }
      payload['exhibitor_id'] = supplierLink['local_id'] as int;
      payload['product_id'] = productLocalId;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('meetings', payload);
      if (link != null) await _db.update('meetings', localId, payload);
      await _db.saveCloudLink('meeting', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }

    for (final quote in await _db.queryAll('quotes')) {
      final localId = quote['id'] as int;
      final productLink =
          await _db.getCloudLink('product', quote['product_id'] as int);
      if (productLink == null) continue;
      final link = await _db.getCloudLink('quote', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final payload = Map<String, dynamic>.from(quote)
        ..remove('id')
        ..remove('product_id')
        ..['product_record_id'] = productLink['record_id'];
      if (await _isUnchanged('quote', localId, recordId, link, payload)) {
        continue;
      }
      try {
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'quote',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'quote', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          await _captureConflict(team.id, 'quote', localId, recordId, payload);
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final quoteRecords = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'quote');
    for (final record in quoteRecords) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('quote', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final contentHash = _payloadHash(payload);
      final productRecordId = payload.remove('product_record_id') as String?;
      if (productRecordId == null) continue;
      final productLink =
          await _db.getCloudLinkByRecordId('product', productRecordId);
      if (productLink == null) continue;
      payload['product_id'] = productLink['local_id'] as int;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('quotes', payload);
      if (link != null) await _db.update('quotes', localId, payload);
      await _db.saveCloudLink('quote', localId, recordId, version,
          contentHash: contentHash);
      downloaded++;
    }

    for (final attachment in await _db.queryAll('attachments')) {
      final localId = attachment['id'] as int;
      final ownerRecordType =
          _ownerRecordType(attachment['owner_type'] as String);
      if (ownerRecordType == null) continue;
      final ownerLink = await _db.getCloudLink(
          ownerRecordType, attachment['owner_id'] as int);
      if (ownerLink == null) continue;
      final localPath = attachment['path'] as String;
      final file = File(localPath);
      if (!await file.exists()) continue;
      final link = await _db.getCloudLink('attachment', localId);
      final recordId = link?['record_id'] as String? ?? _newRecordId();
      final version = link?['version'] as int?;
      final storagePath = _storagePath(team.id, recordId, localPath);
      final payload = Map<String, dynamic>.from(attachment)
        ..remove('id')
        ..remove('owner_id')
        ..remove('path')
        ..['owner_record_type'] = ownerRecordType
        ..['owner_record_id'] = ownerLink['record_id']
        ..['storage_path'] = storagePath;
      if (await _isUnchanged('attachment', localId, recordId, link, payload)) {
        continue;
      }
      try {
        await _client.storage.from(_attachmentBucket).upload(
              storagePath,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
        final response = await _client.rpc('upsert_team_record', params: {
          'target_team': team.id,
          'target_record_type': 'attachment',
          'target_record_id': recordId,
          'target_payload': payload,
          'expected_version': version == null || version == 0 ? null : version,
        });
        final row = (response as List).first as Map<String, dynamic>;
        await _db.saveCloudLink(
            'attachment', localId, recordId, row['version'] as int,
            contentHash: _payloadHash(payload));
        uploaded++;
      } on PostgrestException catch (error) {
        if (error.message.contains('sync_conflict')) {
          await _captureConflict(
              team.id, 'attachment', localId, recordId, payload);
          conflicts++;
        } else {
          rethrow;
        }
      }
    }

    final attachmentRecords = await _client
        .from('team_records')
        .select('record_id, payload, version')
        .eq('team_id', team.id)
        .eq('record_type', 'attachment');
    for (final record in attachmentRecords) {
      final recordId = record['record_id'] as String;
      final version = record['version'] as int;
      final link = await _db.getCloudLinkByRecordId('attachment', recordId);
      if (link != null && (link['version'] as int) >= version) continue;
      final payload = Map<String, Object?>.from(record['payload'] as Map);
      final contentHash = _payloadHash(payload);
      final ownerRecordType = payload.remove('owner_record_type') as String?;
      final ownerRecordId = payload.remove('owner_record_id') as String?;
      final storagePath = payload.remove('storage_path') as String?;
      if (ownerRecordType == null ||
          ownerRecordId == null ||
          storagePath == null) {
        continue;
      }
      final ownerLink =
          await _db.getCloudLinkByRecordId(ownerRecordType, ownerRecordId);
      if (ownerLink == null) continue;
      final ownerType = _localOwnerType(ownerRecordType);
      if (ownerType == null) continue;
      final localPath = await _downloadAttachment(
          storagePath, ownerType, ownerLink['local_id'] as int);
      payload['owner_type'] = ownerType;
      payload['owner_id'] = ownerLink['local_id'] as int;
      payload['path'] = localPath;
      final localId =
          link?['local_id'] as int? ?? await _db.insert('attachments', payload);
      if (link != null) await _db.update('attachments', localId, payload);
      await _db.saveCloudLink('attachment', localId, recordId, version,
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

  Future<List<CloudConflict>> conflicts() async =>
      (await _db.getCloudSyncConflicts()).map(CloudConflict.fromMap).toList();

  Future<void> keepLocalConflict(CloudConflict conflict) async {
    final response = await _client.rpc('upsert_team_record', params: {
      'target_team': conflict.teamId,
      'target_record_type': conflict.recordType,
      'target_record_id': conflict.recordId,
      'target_payload': conflict.localPayload,
      'expected_version': conflict.remoteVersion,
    });
    final row = (response as List).first as Map<String, dynamic>;
    await _db.saveCloudLink(
      conflict.recordType,
      conflict.localId,
      conflict.recordId,
      row['version'] as int,
      contentHash: _payloadHash(conflict.localPayload),
    );
    await _db.deleteCloudSyncConflict(conflict.id);
  }

  Future<void> useCloudConflict(CloudConflict conflict) async {
    final payload = Map<String, Object?>.from(conflict.remotePayload);
    String table;
    switch (conflict.recordType) {
      case 'trip':
        table = 'trips';
        break;
      case 'supplier':
        final tripRecordId = payload.remove('trip_record_id') as String?;
        final tripLink = tripRecordId == null
            ? null
            : await _db.getCloudLinkByRecordId('trip', tripRecordId);
        if (tripLink == null)
          throw StateError('Cloud trip is not available locally.');
        payload['trip_id'] = tripLink['local_id'] as int;
        table = 'exhibitors';
        break;
      case 'contact':
      case 'product':
        final supplierRecordId =
            payload.remove('supplier_record_id') as String?;
        final supplierLink = supplierRecordId == null
            ? null
            : await _db.getCloudLinkByRecordId('supplier', supplierRecordId);
        if (supplierLink == null)
          throw StateError('Cloud supplier is not available locally.');
        payload['exhibitor_id'] = supplierLink['local_id'] as int;
        table = conflict.recordType == 'contact' ? 'contacts' : 'products';
        break;
      case 'quote':
        final productRecordId = payload.remove('product_record_id') as String?;
        final productLink = productRecordId == null
            ? null
            : await _db.getCloudLinkByRecordId('product', productRecordId);
        if (productLink == null)
          throw StateError('Cloud product is not available locally.');
        payload['product_id'] = productLink['local_id'] as int;
        table = 'quotes';
        break;
      case 'meeting':
        final supplierRecordId =
            payload.remove('supplier_record_id') as String?;
        final productRecordId = payload.remove('product_record_id') as String?;
        final supplierLink = supplierRecordId == null
            ? null
            : await _db.getCloudLinkByRecordId('supplier', supplierRecordId);
        if (supplierLink == null) {
          throw StateError('Cloud supplier is not available locally.');
        }
        payload['exhibitor_id'] = supplierLink['local_id'] as int;
        if (productRecordId != null) {
          final productLink =
              await _db.getCloudLinkByRecordId('product', productRecordId);
          if (productLink == null) {
            throw StateError('Cloud product is not available locally.');
          }
          payload['product_id'] = productLink['local_id'] as int;
        } else {
          payload['product_id'] = null;
        }
        table = 'meetings';
        break;
      case 'attachment':
        final ownerRecordType = payload.remove('owner_record_type') as String?;
        final ownerRecordId = payload.remove('owner_record_id') as String?;
        final storagePath = payload.remove('storage_path') as String?;
        final ownerLink = ownerRecordType == null || ownerRecordId == null
            ? null
            : await _db.getCloudLinkByRecordId(ownerRecordType, ownerRecordId);
        final ownerType =
            ownerRecordType == null ? null : _localOwnerType(ownerRecordType);
        if (ownerLink == null || ownerType == null || storagePath == null) {
          throw StateError('Cloud attachment owner is not available locally.');
        }
        payload['owner_type'] = ownerType;
        payload['owner_id'] = ownerLink['local_id'] as int;
        payload['path'] = await _downloadAttachment(
            storagePath, ownerType, ownerLink['local_id'] as int);
        table = 'attachments';
        break;
      default:
        throw StateError(
            'Use cloud is not available for ${conflict.recordType} yet.');
    }
    await _db.update(table, conflict.localId, payload);
    await _db.saveCloudLink(conflict.recordType, conflict.localId,
        conflict.recordId, conflict.remoteVersion,
        contentHash: _payloadHash(conflict.remotePayload));
    await _db.deleteCloudSyncConflict(conflict.id);
  }

  Future<void> _captureConflict(
    String teamId,
    String recordType,
    int localId,
    String recordId,
    Map<String, Object?> localPayload,
  ) async {
    final remote = await _client
        .from('team_records')
        .select('payload, version')
        .eq('team_id', teamId)
        .eq('record_type', recordType)
        .eq('record_id', recordId)
        .single();
    await _db.saveCloudSyncConflict(
      teamId: teamId,
      recordType: recordType,
      localId: localId,
      recordId: recordId,
      localPayload: localPayload,
      remotePayload: Map<String, Object?>.from(remote['payload'] as Map),
      remoteVersion: remote['version'] as int,
    );
  }

  static const _attachmentBucket = 'team-attachments';

  String? _ownerRecordType(String ownerType) => switch (ownerType) {
        'exhibitor' => 'supplier',
        'product' => 'product',
        _ => null,
      };

  String? _localOwnerType(String recordType) => switch (recordType) {
        'supplier' => 'exhibitor',
        'product' => 'product',
        _ => null,
      };

  String _storagePath(String teamId, String recordId, String localPath) {
    final extension = path.extension(localPath).toLowerCase();
    return '$teamId/$recordId/file$extension';
  }

  Future<String> _downloadAttachment(
      String storagePath, String ownerType, int ownerId) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/attachments/$ownerType/$ownerId');
    await directory.create(recursive: true);
    final attachmentId = path.basename(path.dirname(storagePath));
    final target = File(
        '${directory.path}/attachment_$attachmentId${path.extension(storagePath)}');
    if (!await target.exists()) {
      final bytes =
          await _client.storage.from(_attachmentBucket).download(storagePath);
      await target.writeAsBytes(bytes, flush: true);
    }
    return target.path;
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
