part of 'cloud_sync_service.dart';

extension PhoneCopyCleanup on CloudSyncService {
  Future<PhoneCleanupPlan> inspectPhoneCleanup() =>
      TeamWorkspaceService.exclusive(_inspectPhoneCleanup, showBusy: false);

  Future<Map<String, Object?>> _cleanupSnapshot(DatabaseExecutor db) async {
    final result = <String, Object?>{};
    for (final table in [...TradeDatabase.backupTables,
      'cloud_links', 'sync_deletions', 'cloud_sync_conflicts']) {
      final rows = await db.query(table);
      final sorted = rows.map((row) => Map<String, Object?>.from(row)).toList();
      sorted.sort((a, b) => _hash(a).compareTo(_hash(b)));
      result[table] = sorted;
    }
    return result;
  }

  Future<PhoneCleanupPlan> _inspectPhoneCleanup() async {
    final team = await _workspace.load();
    if (team == null) throw StateError('Select a team workspace first.');
    await ApprovalPolicy.requireWriter();
    final scope = await _workspace.scopeKey();
    final db = await _db.database;
    final snapshot = await db.transaction((txn) => _cleanupSnapshot(txn));
    final tables = {...TradeDatabase.syncTables, ...FieldWorkSyncContract.tables};
    final links = <String, Map<String, Object?>>{};
    for (final row in (snapshot['cloud_links'] as List)) {
      final link = Map<String, Object?>.from(row as Map);
      links['${link['record_type']}:${link['local_id']}'] = link;
    }
    final blocked = <String>{};
    for (final table in ['sync_deletions', 'cloud_sync_conflicts']) {
      for (final row in (snapshot[table] as List)) {
        blocked.add('${row['record_type']}:${row['local_id']}');
      }
    }
    final files = <String, String>{};
    final documents = await getApplicationDocumentsDirectory();
    for (final folder in ['attachments', 'product_capture',
      'company_visit_drafts', 'team_files']) {
      final root = Directory(path.join(documents.path, folder, scope));
      if (!await root.exists()) continue;
      final resolvedRoot = await root.resolveSymbolicLinks();
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final resolved = await entity.resolveSymbolicLinks();
        if (!path.isWithin(resolvedRoot, resolved)) continue;
        files[resolved] = sha256.convert(await entity.readAsBytes()).toString();
      }
    }
    final entries = <PhoneCleanupEntry>[];
    final registeredFiles = <String>{};
    for (final table in tables.entries) {
      final remote = <String, Map<String, Object?>>{};
      for (final record in await _records(team.id, table.key)) {
        remote[record['record_id'].toString()] = Map<String, Object?>.from(record);
      }
      for (final raw in (snapshot[table.value] as List)) {
        final row = Map<String, Object?>.from(raw as Map);
        final id = row[FieldWorkSyncContract.primaryKey(table.key)] as int;
        final key = '${table.key}:$id';
        final parents = <String>{};
        for (final relation in (CloudSyncService._relations[table.key] ?? <String, String>{}).entries) {
          if (row[relation.key] != null) parents.add('${relation.value}:${row[relation.key]}');
        }
        if (table.key == 'attachment') {
          final owner = row['owner_type'] == 'exhibitor' ? 'supplier' : row['owner_type'];
          parents.add('$owner:${row['owner_id']}');
          final file = File(row['path'].toString());
          if (await file.exists()) registeredFiles.add(await file.resolveSymbolicLinks());
        }
        var verified = false;
        final link = links[key];
        final cloud = link == null ? null : remote[link['record_id'].toString()];
        if (cloud != null && !blocked.contains(key)) {
          try {
            final payload = await _toCloud(db, table.key, {...row, 'id': id},
              team.id, link!['record_id'].toString());
            verified = _hash(payload) == _hash(cloud['payload']);
            if (verified && table.key == 'attachment') {
              final storagePath = payload['storage_path'].toString();
              if (!storagePath.startsWith('${team.id}/')) {
                verified = false;
              } else {
                final bytes = await _client.storage.from(CloudSyncService._bucket).download(storagePath);
                verified = sha256.convert(bytes).toString() == payload['file_sha256'];
              }
            }
          } catch (_) {
            // A missing file, failed download or unresolved parent is never safe to clear.
            verified = false;
          }
        }
        entries.add(PhoneCleanupEntry(type: table.key, id: id, row: row,
          parents: parents, cloudVerified: verified));
      }
    }
    final unknownFiles = files.keys.where((file) => !registeredFiles.contains(file)).length;
    final auxiliary = TradeDatabase.backupTables.where((table) => !tables.containsValue(table));
    final localOnly = auxiliary.fold<int>(0, (count, table) => count + (snapshot[table] as List).length)
      + (snapshot['sync_deletions'] as List).length
      + (snapshot['cloud_sync_conflicts'] as List).length + unknownFiles;
    final clearable = entries.where((entry) => entry.cloudVerified).map((entry) => entry.key).toSet();
    // Drafts and local history may refer to arbitrary records. Preserve their dependencies
    // conservatively rather than guessing which company/product they reference.
    if (localOnly > 0) clearable.clear();
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in entries.where((entry) => !clearable.contains(entry.key))) {
        for (final parent in entry.parents) {
          if (clearable.remove(parent)) changed = true;
        }
      }
    }
    if (scope != await _workspace.scopeKey()) throw StateError('Workspace changed. Check again.');
    return PhoneCleanupPlan(scope: scope, teamId: team.id,
      manifestHash: sha256.convert(utf8.encode(_hash({'rows': snapshot, 'files': files}))).toString(),
      snapshot: snapshot, entries: entries, files: files,
      clearable: clearable, localOnlyCount: localOnly);
  }

  Future<({int records, int files, List<String> warnings})> clearPhoneCopies(
    PhoneCleanupPlan preview, {String? approvalId}) =>
      TeamWorkspaceService.exclusive(() async {
        final plan = await _inspectPhoneCleanup();
        if (plan.scope != preview.scope || plan.manifestHash != preview.manifestHash) {
          throw StateError('Phone data changed. Check again and request a new approval if needed.');
        }
        final full = approvalId != null;
        final selected = full ? plan.entries.map((entry) => entry.key).toSet() : plan.clearable;
        if (!full && selected.isEmpty) throw StateError('No verified independent phone copies can be cleared.');
        final service = PhoneCleanupService();
        final eventId = await service.begin(plan, approvalId: approvalId);
        final wasPaused = await PhoneCleanupService.paused(plan.scope);
        await PhoneCleanupService.setPaused(plan.scope, true);
        final db = await _db.database;
        var count = 0;
        try {
          await db.transaction((txn) async {
            if (_hash(await _cleanupSnapshot(txn)) != _hash(plan.snapshot)) {
              throw StateError('Phone records changed. Nothing was cleared.');
            }
            // DELETE triggers only queue cloud deletions while a cloud link exists.
            // Remove those links first; this is cache eviction, not a business deletion.
            for (final entry in plan.entries.where((entry) => selected.contains(entry.key))) {
              await txn.delete('cloud_links', where: 'record_type = ? AND local_id = ?',
                whereArgs: [entry.type, entry.id]);
            }
            if (full) {
              await txn.delete('cloud_links');
              await txn.delete('sync_deletions');
              await txn.delete('cloud_sync_conflicts');
              for (final table in TradeDatabase.backupTables.reversed) {
                count += await txn.delete(table);
              }
            } else {
              final tables = {...TradeDatabase.syncTables, ...FieldWorkSyncContract.tables};
              for (final type in tables.keys.toList().reversed) {
                for (final entry in plan.entries.where((entry) => entry.type == type && selected.contains(entry.key))) {
                  count += await txn.delete(tables[type]!,
                    where: '${FieldWorkSyncContract.primaryKey(type)} = ?', whereArgs: [entry.id]);
                }
              }
              final remaining = await _cleanupSnapshot(txn);
              if (_hash(remaining['sync_deletions']) != _hash(plan.snapshot['sync_deletions'])) {
                throw StateError('Cleanup would create a cloud deletion. Nothing was cleared.');
              }
            }
          });
        } catch (_) {
          await PhoneCleanupService.setPaused(plan.scope, wasPaused);
          rethrow;
        }
        final pathsToRemove = <String>{};
        if (full) {
          pathsToRemove.addAll(plan.files.keys);
        } else {
          final attachments = plan.entries.where((entry) => entry.type == 'attachment');
          for (final entry in attachments.where((entry) => selected.contains(entry.key))) {
            final file = File(entry.row['path'].toString());
            if (!await file.exists()) continue;
            final resolved = await file.resolveSymbolicLinks();
            if (!plan.files.containsKey(resolved)) continue;
            final retained = attachments.where((other) => !selected.contains(other.key));
            var shared = false;
            for (final other in retained) {
              final otherFile = File(other.row['path'].toString());
              if (await otherFile.exists() && await otherFile.resolveSymbolicLinks() == resolved) shared = true;
            }
            if (!shared) pathsToRemove.add(resolved);
          }
        }
        var fileCount = 0;
        final warnings = <String>[];
        for (final filePath in pathsToRemove) {
          try {
            final file = File(filePath);
            if (!await file.exists()) continue;
            if (sha256.convert(await file.readAsBytes()).toString() != plan.files[filePath]) {
              warnings.add('A changed file was retained.');
              continue;
            }
            await file.delete();
            fileCount++;
          } catch (_) { warnings.add('A phone file could not be removed.'); }
        }
        try { await service.complete(eventId, count, fileCount, warnings); }
        catch (_) { warnings.add('Phone cleanup finished, but cloud audit completion could not be recorded.'); }
        return (records: count, files: fileCount, warnings: warnings);
      }, showBusy: true);
}
