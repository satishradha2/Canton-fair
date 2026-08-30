import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';

class BackupService {
  static const _tables = [
    'trips',
    'exhibitors',
    'contacts',
    'products',
    'meetings',
    'quotes',
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
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Canton Fair CRM local data backup',
    );
  }
}
