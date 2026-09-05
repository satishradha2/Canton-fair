import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'approval_policy.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';
import 'sync_status_service.dart';
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
  static const _bucket = 'team-attachments';
  static const _deleted = <String, Object?>{'_deleted': true};
  static const _relations = <String, Map<String, String>>{
    'sourcing_brief': {'trip_id': 'trip'},
    'supplier': {'trip_id': 'trip'},
    'contact': {'exhibitor_id': 'supplier'},
    'product': {'exhibitor_id': 'supplier'},
    'meeting': {'exhibitor_id': 'supplier', 'product_id': 'product'},
    'quote': {'product_id': 'product'},
    'sample': {'exhibitor_id': 'supplier', 'product_id': 'product'},
  };

  Future<SyncResult> syncTrips() => syncTeamWorkspace();

  Future<SyncResult> syncTeamWorkspace() => TeamWorkspaceService.exclusive(() async {
    SyncStatusService.setSyncing(true);
    try {
      final result = await _sync();
      await SyncStatusService().recordSuccess(uploaded: result.uploaded,
          downloaded: result.downloaded, conflicts: result.conflicts);
      return result;
    } catch (error) {
      await SyncStatusService().recordFailure(error);
      rethrow;
    } finally {
      SyncStatusService.setSyncing(false);
    }
  });

  Future<SyncResult> _sync() async {
    final team = await _requireTeam();
    final scope = await _workspace.scopeKey();
    final db = await _db.database;
    final role = await ApprovalPolicy.currentRole();
    var uploaded = 0;
    var downloaded = 0;
    final remote = <String, List<Map<String, dynamic>>>{};
    // Read every page, including tombstones. Capture before writes so a
    // subsequent concurrent server change cannot masquerade as our baseline.
    for (final type in TradeDatabase.syncTables.keys) {
      remote[type] = await _records(team.id, type);
    }
    if (role != 'viewer') {
      // Allocate stable IDs before network writes so retries do not duplicate
      // records if a request succeeds but its response is lost.
      for (final entry in TradeDatabase.syncTables.entries) {
        for (final row in await db.query(entry.value)) {
          final id = row['id'] as int;
          if (await _link(db, entry.key, id: id) == null) {
            await _saveLink(db, entry.key, id, _newRecordId(), 0, '');
          }
        }
      }
      final deferredProducts = <Map<String, Object?>>[];
      for (final entry in TradeDatabase.syncTables.entries) {
        for (final row in await db.query(entry.value)) {
          await _assertScope(scope);
          final link = await _link(db, entry.key, id: row['id'] as int);
          if (link == null || await _hasConflict(db, entry.key, link['record_id'] as String)) continue;
          final payload = await _toCloud(db, entry.key, row, team.id, link['record_id'] as String);
          if (_hash(payload) == link['content_hash']) continue;
          if (entry.key == 'product') {
            final plan = ApprovalPolicy.jsonObject(payload['purchase_readiness_json']);
            if (['Ready to order', 'Approved for order'].contains(plan['status'])) {
              deferredProducts.add(row);
              if ((link['version'] as int) > 0) continue;
              payload['purchase_readiness_json'] = jsonEncode({...plan, 'status': 'Needs review'});
            }
          }
          if (await _upload(db, team.id, entry.key, link, payload, scope)) uploaded++;
        }
      }
      // Child deletions precede parent deletions; the server refuses dangling
      // references, including children added by another device.
      for (final type in TradeDatabase.syncTables.keys.toList().reversed) {
        for (final deletion in await db.query('sync_deletions',
            where: 'record_type = ?', whereArgs: [type])) {
          if (await _hasConflict(db, type, deletion['record_id'] as String)) continue;
          final link = await _link(db, type, id: deletion['local_id'] as int);
          if (link == null) continue;
          if (await _upload(db, team.id, type, link, _deleted, scope)) uploaded++;
        }
      }

      for (final row in deferredProducts) {
        final link = await _link(db, 'product', id: row['id'] as int);
        if (link == null || await _hasConflict(db, 'product', link['record_id'] as String)) continue;
        final payload = await _toCloud(db, 'product', row, team.id, link['record_id'] as String);
        if (_hash(payload) != link['content_hash'] &&
            await _upload(db, team.id, 'product', link, payload, scope)) {
          uploaded++;
        }
      }
    }
    for (final entry in TradeDatabase.syncTables.entries) {
      for (final record in remote[entry.key]!) {
        await _assertScope(scope);
        final id = record['record_id'] as String;
        if (await _hasConflict(db, entry.key, id)) continue;
        final link = await _link(db, entry.key, recordId: id);
        if (link != null && (link['version'] as int) >= (record['version'] as int)) continue;
        if (link != null) {
          final local = await _localPayload(db, entry.key, link, team.id);
          if (_hash(local) != link['content_hash'] && _hash(local) != _hash(record['payload'])) {
            await _conflict(db, team.id, entry.key, link, local, record);
            continue;
          }
        }
        await _apply(db, team.id, entry.key, record);
        downloaded++;
      }
    }
    final conflicts = await db.query('cloud_sync_conflicts');
    return SyncResult(uploaded, downloaded, conflicts.length);
  }

  Future<TeamWorkspace> _requireTeam() async {
    final team = await _workspace.load();
    if (team == null) throw StateError('Choose a cloud team before syncing. Personal records stay private.');
    Object? version;
    try {
      version = await _client.rpc('sync_protocol_version');
    } on PostgrestException {
      throw StateError('Apply Supabase migration 010_sync_safety.sql before syncing.');
    }
    if (version != 2) throw StateError('Apply Supabase migration 010_sync_safety.sql before syncing.');
    return team;
  }

  Future<void> _assertScope(String scope) async {
    if (await _workspace.scopeKey() != scope) {
      throw StateError('Account or workspace changed; synchronization stopped.');
    }
  }

  Future<List<Map<String, dynamic>>> _records(String team, String type) async {
    final result = <Map<String, dynamic>>[];
    const size = 500;
    for (var offset = 0;; offset += size) {
      final page = await _client.from('team_records')
          .select('record_id,payload,version').eq('team_id', team)
          .eq('record_type', type).order('record_id').range(offset, offset + size - 1);
      result.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < size) break;
    }
    return result;
  }

  Future<Map<String, dynamic>?> _link(DatabaseExecutor db, String type,
      {int? id, String? recordId}) async {
    final rows = await db.query('cloud_links',
        where: id != null ? 'record_type = ? AND local_id = ?' : 'record_type = ? AND record_id = ?',
        whereArgs: [type, id ?? recordId]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> _saveLink(DatabaseExecutor db, String type, int id,
      String recordId, int version, String hash) async {
    await db.insert('cloud_links', {
      'record_type': type, 'local_id': id, 'record_id': recordId,
      'version': version, 'content_hash': hash,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _hasConflict(DatabaseExecutor db, String type, String id) async =>
      (await db.query('cloud_sync_conflicts',
          where: 'record_type = ? AND record_id = ?', whereArgs: [type, id])).isNotEmpty;

  Future<Map<String, Object?>> _localPayload(Database db, String type,
      Map<String, dynamic> link, String team) async {
    final rows = await db.query(TradeDatabase.syncTables[type]!,
        where: 'id = ?', whereArgs: [link['local_id']]);
    if (rows.isEmpty) return Map<String, Object?>.from(_deleted);
    return _toCloud(db, type, rows.first, team, link['record_id'] as String);
  }

  Future<Map<String, Object?>> _toCloud(DatabaseExecutor db, String type,
      Map<String, Object?> row, String team, String recordId) async {
    final payload = Map<String, Object?>.from(row)..remove('id');
    for (final entry in (_relations[type] ?? const <String, String>{}).entries) {
      final localId = payload.remove(entry.key);
      final foreignKey = '${entry.value}_record_id';
      if (localId == null) {
        payload[foreignKey] = null;
      } else {
        final link = await _link(db, entry.value, id: localId as int);
        if (link == null) throw StateError('Missing ${entry.value} link for $type.');
        payload[foreignKey] = link['record_id'];
      }
    }
    if (type == 'attachment') {
      final ownerType = payload.remove('owner_type') as String;
      final ownerRecordType = ownerType == 'exhibitor' ? 'supplier' : ownerType;
      if (!['supplier', 'contact', 'product'].contains(ownerRecordType)) {
        throw StateError('Unsupported attachment owner.');
      }
      final owner = await _link(db, ownerRecordType, id: payload.remove('owner_id') as int);
      if (owner == null) throw StateError('Attachment owner has not been synchronized.');
      final file = File(payload.remove('path') as String);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      var extension = path.extension(file.path).toLowerCase();
      if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)) extension = '';
      payload['owner_record_type'] = ownerRecordType;
      payload['owner_record_id'] = owner['record_id'];
      payload['file_sha256'] = digest;
      payload['storage_path'] = '$team/$recordId/$digest$extension';
    }
    return payload;
  }

  Future<Map<String, Object?>> _fromCloud(DatabaseExecutor db, String team,
      String type, Map<String, Object?> source) async {
    final payload = Map<String, Object?>.from(source)..remove('id');
    for (final entry in (_relations[type] ?? const <String, String>{}).entries) {
      // Never interpret a legacy device-local foreign key as this device's ID.
      payload.remove(entry.key);
      final foreignId = payload.remove('${entry.value}_record_id');
      final requiredParent = entry.key == 'exhibitor_id' ||
          (type == 'supplier' && entry.key == 'trip_id') ||
          (type == 'quote' && entry.key == 'product_id');
      if (foreignId == null) {
        if (requiredParent) throw StateError('Missing cloud parent for $type.');
        payload[entry.key] = null;
      } else {
        final link = await _link(db, entry.value, recordId: foreignId as String);
        if (link == null) throw StateError('Download the parent before resolving $type.');
        final parent = await db.query(TradeDatabase.syncTables[entry.value]!,
            where: 'id = ?', whereArgs: [link['local_id']]);
        if (parent.isEmpty) throw StateError('The parent of $type was deleted.');
        payload[entry.key] = link['local_id'];
      }
    }
    if (type == 'attachment') {
      final ownerType = payload.remove('owner_record_type') as String?;
      final ownerId = payload.remove('owner_record_id') as String?;
      final storagePath = payload.remove('storage_path') as String?;
      final digest = payload.remove('file_sha256') as String?;
      payload.remove('owner_type');
      if (ownerType == null || ownerId == null || storagePath == null ||
          !['supplier', 'contact', 'product'].contains(ownerType) ||
          !storagePath.startsWith('$team/')) {
        throw StateError('Invalid cloud attachment owner or path.');
      }
      final owner = await _link(db, ownerType, recordId: ownerId);
      if (owner == null) throw StateError('Download the attachment owner first.');
      final bytes = await _client.storage.from(_bucket).download(storagePath);
      if (digest != null && sha256.convert(bytes).toString() != digest) {
        throw StateError('Downloaded attachment checksum mismatch.');
      }
      final root = await getApplicationDocumentsDirectory();
      final fileKey = sha256.convert(utf8.encode(storagePath)).toString();
      final file = File('${root.path}/team_files/${await _workspace.scopeKey()}/$fileKey${path.extension(storagePath)}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      payload['owner_type'] = ownerType == 'supplier' ? 'exhibitor' : ownerType;
      payload['owner_id'] = owner['local_id'];
      payload['path'] = file.path;
    }
    return payload;
  }

  Future<bool> _upload(Database db, String team, String type,
      Map<String, dynamic> link, Map<String, Object?> payload, String scope) async {
    final recordId = link['record_id'] as String;
    final remote = await _client.from('team_records').select('payload,version,record_id')
        .eq('team_id', team).eq('record_type', type).eq('record_id', recordId).maybeSingle();
    // Also makes an ambiguous network retry idempotent.
    if (remote != null && _hash(remote['payload']) == _hash(payload)) {
      await _saveLink(db, type, link['local_id'] as int, recordId,
          remote['version'] as int, _hash(payload));
      if (payload['_deleted'] == true) {
        await db.delete('sync_deletions', where: 'record_type = ? AND local_id = ?',
            whereArgs: [type, link['local_id']]);
      }
      return false;
    }
    if (remote != null && remote['version'] != link['version']) {
      await _conflict(db, team, type, link, payload, remote);
      return false;
    }
    if (type == 'attachment' && payload['_deleted'] != true) {
      final rows = await db.query('attachments', where: 'id = ?', whereArgs: [link['local_id']]);
      final bytes = await File(rows.single['path'] as String).readAsBytes();
      if (sha256.convert(bytes).toString() != payload['file_sha256']) {
        throw StateError('Attachment changed while syncing. Retry.');
      }
      try {
        await _client.storage.from(_bucket).uploadBinary(payload['storage_path'] as String,
            bytes, fileOptions: const FileOptions(upsert: false));
      } on StorageException catch (error) {
        if (error.statusCode != '409' && error.statusCode != 'Duplicate') rethrow;
        final existing = await _client.storage.from(_bucket).download(payload['storage_path'] as String);
        if (sha256.convert(existing).toString() != payload['file_sha256']) rethrow;
      }
    }
    await _assertScope(scope);
    try {
      final response = await _client.rpc('upsert_team_record_v2', params: {
        'target_team': team, 'target_record_type': type, 'target_record_id': recordId,
        'target_payload': payload, 'expected_version': link['version'],
      });
      final version = ((response as List).single as Map)['version'] as int;
      await _saveLink(db, type, link['local_id'] as int, recordId, version, _hash(payload));
      if (payload['_deleted'] == true) {
        await db.delete('sync_deletions', where: 'record_type = ? AND local_id = ?',
            whereArgs: [type, link['local_id']]);
      }
      return true;
    } on PostgrestException catch (error) {
      if (!error.message.contains('sync_conflict')) rethrow;
      final latest = await _client.from('team_records').select('payload,version,record_id')
          .eq('team_id', team).eq('record_type', type).eq('record_id', recordId).single();
      await _conflict(db, team, type, link, payload, latest);
      return false;
    }
  }

  Future<void> _conflict(DatabaseExecutor db, String team, String type,
      Map<String, dynamic> link, Map<String, Object?> local, Map<String, dynamic> remote) async {
    await db.insert('cloud_sync_conflicts', {
      'team_id': team, 'record_type': type, 'local_id': link['local_id'],
      'record_id': link['record_id'], 'local_payload': jsonEncode(local),
      'remote_payload': jsonEncode(remote['payload']), 'remote_version': remote['version'],
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _apply(Database db, String team, String type, Map<String, dynamic> record) async {
    final source = Map<String, Object?>.from(record['payload'] as Map);
    final recordId = record['record_id'] as String;
    final link = await _link(db, type, recordId: recordId);
    final table = TradeDatabase.syncTables[type]!;
    final payload = source['_deleted'] == true ? null : await _fromCloud(db, team, type, source);
    await db.transaction((txn) async {
      int? localId = link?['local_id'] as int?;
      if (payload == null) {
        if (localId == null) return; // Unknown tombstone needs no local row.
        await txn.delete(table, where: 'id = ?', whereArgs: [localId]);
      } else if (localId == null) {
        localId = await txn.insert(table, payload);
      } else {
        final rows = await txn.query(table, where: 'id = ?', whereArgs: [localId]);
        if (rows.isEmpty) {
          await txn.insert(table, {...payload, 'id': localId});
        } else {
          await txn.update(table, payload, where: 'id = ?', whereArgs: [localId]);
        }
      }
      await _saveLink(txn, type, localId, recordId, record['version'] as int, _hash(source));
      await txn.delete('sync_deletions', where: 'record_type = ? AND local_id = ?',
          whereArgs: [type, localId]);
    });
  }

  Future<List<CloudConflict>> conflicts() async =>
      (await _db.getCloudSyncConflicts()).map(CloudConflict.fromMap).toList();

  Future<void> keepLocalConflict(CloudConflict conflict) => _resolve(conflict, keepLocal: true);
  Future<void> useCloudConflict(CloudConflict conflict) => _resolve(conflict, keepLocal: false);

  Future<void> _resolve(CloudConflict conflict, {required bool keepLocal}) =>
      TeamWorkspaceService.exclusive(() async {
        final team = await _requireTeam();
        if (team.id != conflict.teamId) throw StateError('This conflict belongs to another team.');
        final scope = await _workspace.scopeKey();
        final db = await _db.database;
        final latest = await _client.from('team_records').select('payload,version,record_id')
            .eq('team_id', team.id).eq('record_type', conflict.recordType)
            .eq('record_id', conflict.recordId).single();
        final link = await _link(db, conflict.recordType, id: conflict.localId);
        if (link == null) throw StateError('Conflict record no longer exists.');
        final local = await _localPayload(db, conflict.recordType, link, team.id);
        if (latest['version'] != conflict.remoteVersion) {
          await _conflict(db, team.id, conflict.recordType, link, local, latest);
          throw StateError('Cloud changed again. Refresh and review the latest conflict.');
        }
        if (keepLocal) {
          await ApprovalPolicy.requireWriter();
          final selected = {...link, 'version': latest['version']};
          await _upload(db, team.id, conflict.recordType, selected, local, scope);
          final updated = await _link(db, conflict.recordType, id: conflict.localId);
          if (updated?['content_hash'] != _hash(local)) {
            throw StateError('The cloud changed again. Review the refreshed conflict.');
          }
          // Local data is already the current version chosen by the user.
          // Do not replace it with an older conflict snapshot.
        } else {
          await _assertScope(scope);
          await _apply(db, team.id, conflict.recordType, latest);
        }
        await db.delete('cloud_sync_conflicts', where: 'id = ?', whereArgs: [conflict.id]);
      });

  String _newRecordId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hash(Object? value) => jsonEncode(_canonical(value));
  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}
