import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class BackupService {
  static const _backupChannel = MethodChannel('canton_fair_crm/backup');
  static const _maxBytes = 256 * 1024 * 1024;
  static const _fieldWorkTables = {
    'product_categories',
    'supplier_participations',
    'exhibitor_booths',
    'visit_plans',
    'visit_sessions',
    'product_category_assignments',
  };
  final TradeDatabase _database;
  BackupService({TradeDatabase? database})
      : _database = database ?? TradeDatabase.instance;

  Future<File> createBackup() => TeamWorkspaceService.exclusive(_createBackup);

  Future<File> _createBackup() async {
    final tables = await _database.backupSnapshot();
    final files = <String, Object?>{};
    var total = 0;
    for (final row in tables['attachments']!) {
      final file = File(row['path'] as String);
      if (!await file.exists()) {
        throw StateError(
            'Attachment ${row['id']} is missing. Restore the file before making a complete backup.');
      }
      total += await file.length();
      if (total > _maxBytes) {
        throw StateError('Backup attachments exceed the 256 MB safety limit.');
      }
      final bytes = await file.readAsBytes();
      files[row['id'].toString()] = {
        'data': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
        'extension': p.extension(file.path),
      };
    }
    final payload = {
      'format': 'canton-fair-crm-backup',
      'version': 4,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'files': files,
    };
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
        '${directory.path}/backups/canton_fair_${DateTime.now().microsecondsSinceEpoch}.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }

  Future<void> createAndShareBackup() async {
    final file = await createBackup();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'Canton Fair CRM portable backup',
    ));
  }

  Future<void> createAndShareEncryptedBackup(String password) async {
    if (password.length < 8) {
      throw const FormatException(
          'Use a backup password of at least 8 characters.');
    }
    final source = await createBackup();
    final clearText = await source.readAsBytes();
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final kdf = cryptography.Pbkdf2(
      macAlgorithm: cryptography.Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    final key =
        await kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final cipher = cryptography.AesGcm.with256bits();
    final box = await cipher.encrypt(clearText, secretKey: key);
    final envelope = {
      'format': 'canton-fair-crm-encrypted-backup',
      'version': 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': 210000,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    final target = File(source.path.replaceFirst('.json', '.encrypted.json'));
    await target.writeAsString(jsonEncode(envelope), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(target.path)],
      text: 'Password-encrypted Canton Fair CRM backup',
    ));
  }

  Future<BackupPreview?> selectBackup() async {
    final path = await _backupChannel.invokeMethod<String>('pickBackup');
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > _maxBytes * 2) {
      throw const FormatException('Backup exceeds the supported size limit.');
    }
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map &&
        decoded['format'] == 'canton-fair-crm-encrypted-backup') {
      throw BackupPasswordRequired(file, Map<String, dynamic>.from(decoded));
    }
    return _decodeBackup(content);
  }

  Future<BackupPreview> unlockBackup(
      BackupPasswordRequired request, String password) async {
    try {
      final data = request.envelope;
      final salt = base64Decode(data['salt'] as String);
      final kdf = cryptography.Pbkdf2(
        macAlgorithm: cryptography.Hmac.sha256(),
        iterations: data['iterations'] as int? ?? 210000,
        bits: 256,
      );
      final key =
          await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final clearText = await cryptography.AesGcm.with256bits().decrypt(
        cryptography.SecretBox(
          base64Decode(data['ciphertext'] as String),
          nonce: base64Decode(data['nonce'] as String),
          mac: cryptography.Mac(base64Decode(data['mac'] as String)),
        ),
        secretKey: key,
      );
      return _decodeBackup(utf8.decode(clearText));
    } catch (_) {
      throw const FormatException(
          'Incorrect password or damaged encrypted backup.');
    }
  }

  Future<int> restoreReplacingLocalData(BackupPreview backup) =>
      TeamWorkspaceService.exclusive(() async {
        if (await TeamWorkspaceService().load() != null) {
          throw StateError(
              'Choose Personal workspace before restoring. Shared team data is not replaced by a local backup.');
        }
        final tables = {
          for (final entry in backup.tables.entries)
            entry.key: entry.value
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
        };
        final current = await _database.backupSnapshot();
        for (final table in TradeDatabase.backupTables) {
          if (!tables.containsKey(table) && current[table]!.isNotEmpty) {
            throw FormatException(
                'This legacy backup has no $table section. Restore would lose existing records.');
          }
          tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
        }
        _validateRelations(tables);
        final root = await getApplicationDocumentsDirectory();
        final directory = Directory(
            '${root.path}/restored_files/${DateTime.now().microsecondsSinceEpoch}');
        var restoredBytes = 0;
        try {
          for (final attachment in tables['attachments']!) {
            if (backup.version == 1) {
              if (!await File(attachment['path'] as String).exists()) {
                throw const FormatException(
                    'Legacy backup attachment files are missing. Version 1 backups are not portable.');
              }
              continue;
            }
            final entry = backup.files[attachment['id'].toString()];
            if (entry is! Map || entry['data'] is! String) {
              throw const FormatException('Attachment bytes are missing.');
            }
            final encoded = entry['data'] as String;
            if (encoded.length > (_maxBytes * 4 / 3 + 4)) {
              throw const FormatException(
                  'Attachment exceeds the backup size limit.');
            }
            final bytes = base64Decode(encoded);
            restoredBytes += bytes.length;
            if (restoredBytes > _maxBytes) {
              throw const FormatException(
                  'Attachments exceed the 256 MB limit.');
            }
            if (sha256.convert(bytes).toString() != entry['sha256']) {
              throw const FormatException(
                  'An attachment checksum does not match.');
            }
            final ext = entry['extension']?.toString() ?? '';
            if (!RegExp(r'^\.[a-zA-Z0-9]{1,12}$').hasMatch(ext) &&
                ext.isNotEmpty) {
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
    if (decoded is! Map ||
        decoded['format'] != 'canton-fair-crm-backup' ||
        ![1, 2, 3, 4].contains(decoded['version']) ||
        decoded['tables'] is! Map) {
      throw const FormatException('Unsupported Canton Fair CRM backup.');
    }
    final version = decoded['version'] as int;
    final rawTables = decoded['tables'] as Map;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in TradeDatabase.backupTables) {
      if (!rawTables.containsKey(table)) {
        if (version == 4 ||
            (version == 3 && !_fieldWorkTables.contains(table))) {
          throw FormatException('Missing $table section.');
        }
        continue;
      }
      final rows = rawTables[table];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('Invalid $table section.');
      }
      tables[table] =
          rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }
    for (final required in [
      'trips',
      'exhibitors',
      'contacts',
      'products',
      'meetings',
      'quotes',
      'attachments'
    ]) {
      if (!tables.containsKey(required)) {
        throw FormatException('Missing $required section.');
      }
    }
    final createdAt =
        DateTime.tryParse(decoded['created_at']?.toString() ?? '');
    if (createdAt == null) {
      throw const FormatException('Missing creation date.');
    }
    return BackupPreview(
        tables: tables,
        createdAt: createdAt,
        version: version,
        files: Map<String, dynamic>.from(decoded['files'] as Map? ?? {}));
  }

  void _validateRelations(Map<String, List<Map<String, dynamic>>> tables) {
    final ids = <String, Set<int>>{};
    for (final entry in tables.entries) {
      final key = switch (entry.key) {
        'trip_closeouts' => 'trip_id',
        'product_category_assignments' => 'product_id',
        _ => 'id',
      };
      final set = <int>{};
      for (final row in entry.value) {
        final id = row[key];
        if (id is! int || id <= 0 || !set.add(id)) {
          throw FormatException('Invalid or duplicate ID in ${entry.key}.');
        }
      }
      ids[entry.key] = set;
    }
    void require(String table, String column, String parent,
        {bool nullable = false}) {
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
    require('supplier_comments', 'exhibitor_id', 'exhibitors');
    require('due_diligence_checks', 'exhibitor_id', 'exhibitors');
    require('rfqs', 'trip_id', 'trips', nullable: true);
    require('expenses', 'trip_id', 'trips', nullable: true);
    require('expenses', 'exhibitor_id', 'exhibitors', nullable: true);
    require('supplier_participations', 'exhibitor_id', 'exhibitors');
    require('supplier_participations', 'trip_id', 'trips');
    require('exhibitor_booths', 'participation_id', 'supplier_participations');
    require('visit_plans', 'booth_id', 'exhibitor_booths');
    require('visit_sessions', 'participation_id', 'supplier_participations');
    require('visit_sessions', 'booth_id', 'exhibitor_booths', nullable: true);
    require('visit_sessions', 'plan_id', 'visit_plans', nullable: true);
    require('product_category_assignments', 'product_id', 'products');
    require('product_category_assignments', 'category_id', 'product_categories');

    final booths = {
      for (final row in tables['exhibitor_booths']!) row['id']: row,
    };
    final plans = {
      for (final row in tables['visit_plans']!) row['id']: row,
    };
    for (final session in tables['visit_sessions']!) {
      final boothId = session['booth_id'];
      final planId = session['plan_id'];
      if (boothId != null &&
          booths[boothId]!['participation_id'] != session['participation_id']) {
        throw const FormatException('Visit booth belongs to another exhibitor participation.');
      }
      if (planId != null) {
        final planBoothId = plans[planId]!['booth_id'];
        if (booths[planBoothId]!['participation_id'] !=
                session['participation_id'] ||
            (boothId != null && planBoothId != boothId)) {
          throw const FormatException('Visit plan does not match the visit participation or booth.');
        }
      }
    }
    for (final row in tables['attachments']!) {
      final table = {
        'exhibitor': 'exhibitors',
        'product': 'products',
        'contact': 'contacts',
        'expense': 'expenses',
      }[row['owner_type']];
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
  const BackupPreview(
      {required this.tables,
      required this.createdAt,
      this.version = 1,
      this.files = const {}});
  int get recordCount =>
      tables.values.fold(0, (total, rows) => total + rows.length);
}

class BackupPasswordRequired implements Exception {
  final File file;
  final Map<String, dynamic> envelope;
  const BackupPasswordRequired(this.file, this.envelope);
}
