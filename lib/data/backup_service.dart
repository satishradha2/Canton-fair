import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';

class BackupService {
  static const _backupChannel = MethodChannel('canton_fair_crm/backup');
  static const _tables = [
    'trips',
    'exhibitors',
    'contacts',
    'products',
    'meetings',
    'quotes',
    'samples',
    'attachments',
    'saved_supplier_filters',
  ];

  final TradeDatabase _database;

  BackupService({TradeDatabase? database})
      : _database = database ?? TradeDatabase.instance;

  Future<File> createBackup() async {
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables) {
      tables[table] = await _database.queryAll(table);
    }
    final payload = {
      'format': 'canton-fair-crm-backup',
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'tables': tables,
    };
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/canton_fair_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    await _database.logAudit(
      'Backup exported',
      'Local JSON backup created with ${tables.values.fold<int>(0, (total, rows) => total + rows.length)} records.',
    );
    return file;
  }

  Future<void> createAndShareBackup() async {
    final file = await createBackup();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'Canton Fair CRM local data backup',
    ));
  }

  Future<BackupPreview?> selectBackup() async {
    final path = await _backupChannel.invokeMethod<String>('pickBackup');
    if (path == null) return null;
    final content = await File(path).readAsString();
    return _decodeBackup(content);
  }

  Future<int> restoreReplacingLocalData(BackupPreview backup) async {
    final restored = await _database.replaceWithBackup(backup.tables);
    await _database.logAudit(
      'Backup restored',
      'Replaced local records with $restored records from ${backup.createdAt}.',
    );
    return restored;
  }

  BackupPreview _decodeBackup(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['format'] != 'canton-fair-crm-backup') {
      throw const FormatException('This is not a Canton Fair CRM backup file.');
    }
    if (decoded['version'] != 1 || decoded['tables'] is! Map) {
      throw const FormatException('This backup format is not supported.');
    }
    final rawTables = decoded['tables'] as Map;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables) {
      final rows = rawTables[table] ?? const [];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('The $table section is invalid.');
      }
      tables[table] =
          rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }
    final createdAt = DateTime.tryParse(decoded['created_at'] as String? ?? '');
    if (createdAt == null) {
      throw const FormatException('The backup creation date is missing.');
    }
    return BackupPreview(tables: tables, createdAt: createdAt);
  }
}

class BackupPreview {
  final Map<String, List<Map<String, dynamic>>> tables;
  final DateTime createdAt;

  const BackupPreview({required this.tables, required this.createdAt});

  int get recordCount =>
      tables.values.fold(0, (total, rows) => total + rows.length);
}
