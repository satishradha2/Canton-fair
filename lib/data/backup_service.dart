import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class BackupService {
  static const _backupChannel = MethodChannel('canton_fair_crm/backup');
  static const _maxBytes = 256 * 1024 * 1024;
  final TradeDatabase _database;
  BackupService({TradeDatabase? database}) : _database = database ?? TradeDatabase.instance;

  Future<File> createBackup() => TeamWorkspaceService.exclusive(_createBackup);

  Future<File> _createBackup() async {
    final tables = await _database.backupSnapshot();
    final files = <String, Object?>{};
    var total = 0;
    for (final row in tables['attachments']!) {
      final file = File(row['path'] as String);
      if (!await file.exists()) {
        throw StateError('Attachment ${row['id']} is missing. Restore the file before making a complete backup.');
      }
      total += await file.length();
      if (total > _maxBytes) throw StateError('Backup attachments exceed the 256 MB safety limit.');
      final bytes = await file.readAsBytes();
      files[row['id'].toString()] = {
        'data': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
        'extension': p.extension(file.path),
      };
    }
    final payload = {
      'format': 'canton-fair-crm-backup', 'version': 2,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables, 'files': files,
    };
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/backups/canton_fair_${DateTime.now().microsecondsSinceEpoch}.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }

  Future<void> createAndShareBackup() async {
    final file = await createBackup();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)], text: 'Canton Fair CRM portable backup',
    ));
  }

  Future<BackupPreview?> selectBackup() async {
    final path = await _backupChannel.invokeMethod<String>('pickBackup');
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > _maxBytes * 2) {
      throw const FormatException('Backup exceeds the supported size limit.');
    }
    return _decodeBackup(await file.readAsString());
  }

  Future<int> restoreReplacingLocalData(BackupPreview backup) =>
      TeamWorkspaceService.exclusive(() async {
        if (await TeamWorkspaceService().load() != null) {
          throw StateError('Choose Personal workspace before restoring. Shared team data is not replaced by a local backup.');
        }
        final tables = {
          for (final entry in backup.tables.entries)
            entry.key: entry.value.map((row) => Map<String, dynamic>.from(row)).toList(),
        };
        final current = await _database.backupSnapshot();
        for (final table in TradeDatabase.backupTables) {
          if (!tables.containsKey(table) && current[table]!.isNotEmpty) {
            throw FormatException('This legacy backup has no $table section. Restore would lose existing records.');
          }
          tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
        }
        _validateRelations(tables);
        final root = await getApplicationDocumentsDirectory();
        final directory = Directory('${root.path}/restored_files/${DateTime.now().microsecondsSinceEpoch}');
        var restoredBytes = 0;
        try {
          for (final attachment in tables['attachments']!) {
            if (backup.version == 1) {
              if (!await File(attachment['path'] as String).exists()) {
                throw const FormatException('Legacy backup attachment files are missing. Version 1 backups are not portable.');
              }
              continue;
            }
            final entry = backup.files[attachment['id'].toString()];
            if (entry is! Map || entry['data'] is! String) {
              throw const FormatException('Attachment bytes are missing.');
            }
            final encoded = entry['data'] as String;
            if (encoded.length > (_maxBytes * 4 / 3 + 4)) {
              throw const FormatException('Attachment exceeds the backup size limit.');
            }
            final bytes = base64Decode(encoded);
            restoredBytes += bytes.length;
            if (restoredBytes > _maxBytes) {
              throw const FormatException('Attachments exceed the 256 MB limit.');
            }
            if (sha256.convert(bytes).toString() != entry['sha256']) {
              throw const FormatException('An attachment checksum does not match.');
            }
            final ext = entry['extension']?.toString() ?? '';
            if (!RegExp(r'^\.[a-zA-Z0-9]{1,12}$').hasMatch(ext) && ext.isNotEmpty) {
              throw const FormatException('Invalid attachment extension.');
            }
            final file = File('${directory.path}/${attachment['id']}$ext');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            attachment['path'] = file.path;
          }
          // Keep a complete recovery copy before any destructive database step.
          // If existing media is missing, do not proceed with replacement.
          await _createBackup();
          final count = await _database.replaceWithBackup(tables);
          await _database.logAudit('Backup restored',
              'Restored $count records. Pre-restore backup retained in app documents/backups.');
          return count;
        } catch (_) {
          // Do not delete staged files: a post-commit audit failure must not
          // remove files already referenced by restored records.
          rethrow;
        }
      });

  BackupPreview _decodeBackup(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['format'] != 'canton-fair-crm-backup' ||
        ![1, 2].contains(decoded['version']) || decoded['tables'] is! Map) {
      throw const FormatException('Unsupported Canton Fair CRM backup.');
    }
    final version = decoded['version'] as int;
    final rawTables = decoded['tables'] as Map;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in TradeDatabase.backupTables) {
      if (!rawTables.containsKey(table)) {
        if (version == 2) throw FormatException('Missing $table section.');
        continue;
      }
      final rows = rawTables[table];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('Invalid $table section.');
      }
      tables[table] = rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }
    for (final required in ['trips', 'exhibitors', 'contacts', 'products', 'meetings', 'quotes', 'attachments']) {
      if (!tables.containsKey(required)) throw FormatException('Missing $required section.');
    }
    final createdAt = DateTime.tryParse(decoded['created_at']?.toString() ?? '');
    if (createdAt == null) throw const FormatException('Missing creation date.');
    return BackupPreview(tables: tables, createdAt: createdAt, version: version,
        files: Map<String, dynamic>.from(decoded['files'] as Map? ?? {}));
  }

  void _validateRelations(Map<String, List<Map<String, dynamic>>> tables) {
    final ids = <String, Set<int>>{};
    for (final entry in tables.entries) {
      final key = entry.key == 'trip_closeouts' ? 'trip_id' : 'id';
      final set = <int>{};
      for (final row in entry.value) {
        final id = row[key];
        if (id is! int || id <= 0 || !set.add(id)) {
          throw FormatException('Invalid or duplicate ID in ${entry.key}.');
        }
      }
      ids[entry.key] = set;
    }
    void require(String table, String column, String parent, {bool nullable = false}) {
      for (final row in tables[table]!) {
        if (nullable && row[column] == null) continue;
        if (!ids[parent]!.contains(row[column])) {
          throw FormatException('Broken $table.$column relationship.');
        }
      }
    }
    require('exhibitors', 'trip_id', 'trips');
    require('sourcing_briefs', 'trip_id', 'trips', nullable: true);
    require('trip_closeouts', 'trip_id', 'trips');
    for (final table in ['contacts', 'products', 'meetings', 'samples']) {
      require(table, 'exhibitor_id', 'exhibitors');
    }
    require('quotes', 'product_id', 'products');
    require('meetings', 'product_id', 'products', nullable: true);
    require('samples', 'product_id', 'products', nullable: true);
    for (final row in tables['attachments']!) {
      final table = {'exhibitor': 'exhibitors', 'product': 'products', 'contact': 'contacts'}[row['owner_type']];
      if (table == null || !ids[table]!.contains(row['owner_id'])) {
        throw const FormatException('Broken attachment owner relationship.');
      }
    }
  }
}

class BackupPreview {
  final Map<String, List<Map<String, dynamic>>> tables;
  final DateTime createdAt;
  final int version;
  final Map<String, dynamic> files;
  const BackupPreview({required this.tables, required this.createdAt,
    this.version = 1, this.files = const {}});
  int get recordCount => tables.values.fold(0, (total, rows) => total + rows.length);
}
