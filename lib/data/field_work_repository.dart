import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class FieldWorkSnapshot {
  const FieldWorkSnapshot(this.scope, this.trips, this.tripId, this.booths);
  final String scope;
  final List<Map<String, Object?>> trips;
  final int? tripId;
  final List<Map<String, Object?>> booths;
}

class FieldWorkRepository {
  final _workspace = TeamWorkspaceService();

  Future<Map<String, Object?>> prepareRecording(String scope, int visit,
      String kind) => _write(scope, (txn) async {
    if (!['conversation', 'voice_note'].contains(kind)) {
      throw StateError('Invalid recording type.');
    }
    final owner = Supabase.instance.client.auth.currentUser?.email ?? '';
    final sessions = await txn.rawQuery('''SELECT s.*,p.exhibitor_id FROM visit_sessions s
      JOIN supplier_participations p ON p.id=s.participation_id
      WHERE s.id=? AND s.status='in_progress' AND s.owner_email=?''', [visit, owner]);
    if (sessions.isEmpty) throw StateError('Start your own visit before recording.');
    final links = await txn.query('cloud_links',
      where: "record_type='visit_session' AND local_id=?", whereArgs: [visit]);
    final random = Random.secure();
    String identity() => List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0')).join();
    final visitRecord = links.isEmpty ? identity() : links.first['record_id'] as String;
    if (links.isEmpty) {
      await txn.insert('cloud_links', {
        'record_type': 'visit_session', 'local_id': visit, 'record_id': visitRecord,
        'version': 0, 'content_hash': '',
      });
    }
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(paths.join(root.path, 'attachments', scope, 'visit_audio'));
    await folder.create(recursive: true);
    final id = identity();
    final metadata = <String, Object?>{
      'format': 'canton-visit-audio-v1', 'recording_id': id,
      'visit_record_id': visitRecord, 'supplier_id': sessions.first['exhibitor_id'],
      'kind': kind, 'owner_email': owner,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'scope': scope, 'path': paths.join(folder.path, '$id.m4a'),
    };
    // Recovery metadata is written before the microphone starts. This is local
    // staging, not a synchronized attachment until audio is finalized.
    await File('${metadata['path']}.pending.json')
        .writeAsString(jsonEncode(metadata), flush: true);
    return metadata;
  });

  Future<void> saveRecording(String scope, Map<String, Object?> metadata,
      String notes) => TeamWorkspaceService.exclusive(() async {
    await _check(scope);
    if (metadata['scope'] != scope) throw StateError('Recording belongs to another workspace.');
    final file = File(metadata['path'] as String);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('No finalized audio is available. The recovery marker is retained.');
    }
    final root = await getApplicationDocumentsDirectory();
    final folder = paths.join(root.path, 'attachments', scope, 'visit_audio');
    if (!paths.isWithin(folder, file.path)) throw StateError('Invalid recording path.');
    final db = await TradeDatabase.instance.database;
    await _check(scope);
    await db.transaction((txn) async {
      final supplier = metadata['supplier_id'] as int;
      if ((await txn.query('exhibitors', where: 'id=?', whereArgs: [supplier])).isEmpty) {
        throw StateError('Supplier was removed. Audio remains on this device.');
      }
      final note = jsonEncode({
        'format': metadata['format'], 'recording_id': metadata['recording_id'],
        'visit_record_id': metadata['visit_record_id'], 'kind': metadata['kind'],
        'owner_email': metadata['owner_email'], 'started_at': metadata['started_at'],
        'ended_at': metadata['ended_at'], 'consent_confirmed': true, 'notes': notes,
      });
      final existing = await txn.query('attachments',
        where: 'path=? AND owner_type=? AND owner_id=?',
        whereArgs: [file.path, 'exhibitor', supplier]);
      if (existing.isEmpty) {
        await txn.insert('attachments', {'owner_type': 'exhibitor', 'owner_id': supplier,
          'kind': 'audio', 'path': file.path, 'note': note});
      } else {
        await txn.update('attachments', {'note': note},
          where: 'id=?', whereArgs: [existing.first['id']]);
      }
    });
    // If cleanup fails, retry is safe: attachment creation above is idempotent.
    final marker = File('${file.path}.pending.json');
    if (await marker.exists()) await marker.delete();
  });

  Future<int> captureProduct({
    required String scope,
    required int supplier,
    required Map<String, String> fields,
    required int rating,
    required bool shortlisted,
    required List<String> photos,
  }) => _write(scope, (txn) async {
    String value(String key) => fields[key]?.trim() ?? '';
    final name = value('name');
    final categoryName = value('category').replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || categoryName.isEmpty || categoryName.length > 100) {
      throw const FormatException('Product name and category are required.');
    }
    if (rating < 0 || rating > 5) throw const FormatException('Invalid rating.');
    double? number(String key) {
      if (value(key).isEmpty) return null;
      final parsed = double.tryParse(value(key));
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Enter a valid non-negative $key.');
      }
      return parsed;
    }
    final price = number('quoted_price');
    final moq = number('moq');
    final currency = value('price_currency').toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Enter a three-letter currency code.');
    }
    if ((await txn.query('exhibitors', where: 'id=?',
        whereArgs: [supplier])).isEmpty) {
      throw StateError('Supplier was removed.');
    }
    final categories = await txn.query('product_categories',
        where: 'normalized_name=?', whereArgs: [categoryName.toLowerCase()]);
    if (categories.isNotEmpty && categories.first['archived'] == 1) {
      throw StateError('This category is archived. Choose another.');
    }
      final category = categories.isEmpty
          ? await txn.insert('product_categories', {'name': categoryName,
              'normalized_name': categoryName.toLowerCase()})
          : categories.first['id'] as int;
      final modelCode = value('model_code');
      final duplicate = await txn.query('products',
          columns: const ['id', 'name', 'model_code'],
          where: '''exhibitor_id = ?
              AND lower(trim(name)) = ?
              AND lower(trim(coalesce(model_code, ''))) = ?''',
          whereArgs: [supplier, name.toLowerCase(), modelCode.toLowerCase()],
          limit: 1);
      if (duplicate.isNotEmpty) {
        throw StateError(
            'This supplier already has "$name" with the same model/SKU. Open the existing product instead of saving a duplicate.');
      }
      final product = await txn.insert('products', {
        'exhibitor_id': supplier, 'name': name, 'model_code': modelCode,
      'specs': value('specs'), 'moq': moq, 'quoted_price': price,
      'price_currency': currency, 'lead_time': value('lead_time'),
      'payment_terms': value('payment_terms'), 'rating': rating,
      'shortlisted': shortlisted ? 1 : 0,
      'details_json': jsonEncode({for (final key in [
        'materials', 'dimensions', 'colours', 'variants', 'packaging',
        'carton_dimensions', 'carton_weight', 'units_per_carton', 'quantity_unit',
        'price_basis', 'price_breaks', 'customisation', 'tooling_cost',
        'sample_requirements', 'shortlist_reason', 'notes',
      ]) key: value(key)}),
    });
    await txn.insert('product_category_assignments',
        {'product_id': product, 'category_id': category});
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(paths.join(root.path, 'attachments', scope,
        'field_products', '${DateTime.now().microsecondsSinceEpoch}_$product'));
    for (var i = 0; i < photos.length; i++) {
      final source = File(photos[i]);
      if (!await source.exists()) throw StateError('A selected photo is missing. Retake it before saving.');
      await folder.create(recursive: true);
      final extension = paths.extension(source.path).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)
          ? extension : '.jpg';
      final stored = await source.copy(paths.join(folder.path, '$i$safeExtension'));
      await txn.insert('attachments', {'owner_type': 'product', 'owner_id': product,
        'kind': 'image', 'path': stored.path, 'note': 'Field product photo: $name'});
    }
    return product;
  });

  Future<void> _check(String scope) async {
    if (scope != await _workspace.scopeKey()) {
      throw StateError('Workspace changed. Reopen field visits.');
    }
  }

  Future<T> _write<T>(String scope,
      Future<T> Function(Transaction txn) action) =>
      TeamWorkspaceService.exclusive(() async {
        await _check(scope);
        await ApprovalPolicy.requireWriter();
        final db = await TradeDatabase.instance.database;
        await _check(scope);
        return db.transaction(action);
      });

  Future<FieldWorkSnapshot> load(int? requestedTrip) async {
    final scope = await _workspace.scopeKey();
    final db = await TradeDatabase.instance.database;
    final trips = await db.query('trips', orderBy: 'start_date DESC, id DESC');
    final trip = trips.any((row) => row['id'] == requestedTrip)
        ? requestedTrip : (trips.isEmpty ? null : trips.first['id'] as int);
    final booths = trip == null ? <Map<String, Object?>>[] : await db.rawQuery('''
      SELECT b.*, p.exhibitor_id, e.name,
        COALESCE((SELECT MAX(v.priority) FROM visit_plans v
          WHERE v.booth_id=b.id AND v.selected=1),0) AS priority,
        EXISTS(SELECT 1 FROM visit_plans v
          WHERE v.booth_id=b.id AND v.selected=1) AS selected,
        (SELECT s.id FROM visit_sessions s WHERE s.booth_id=b.id
          AND s.status='in_progress' ORDER BY s.id DESC LIMIT 1) AS active_visit,
        EXISTS(SELECT 1 FROM visit_sessions s WHERE s.booth_id=b.id
          AND s.status='completed') AS visited
      FROM exhibitor_booths b
      JOIN supplier_participations p ON p.id=b.participation_id
      JOIN exhibitors e ON e.id=p.exhibitor_id
      WHERE p.trip_id=? ORDER BY priority DESC, b.booth, e.name
    ''', [trip]);
    await _check(scope);
    return FieldWorkSnapshot(scope, trips, trip, booths);
  }

  /// Explicitly includes suppliers added since the schema migration.
  Future<void> includeTripSuppliers(String scope, int trip) =>
      _write(scope, (txn) async {
        await txn.rawInsert('''INSERT OR IGNORE INTO supplier_participations
          (exhibitor_id, trip_id, source)
          SELECT e.id,e.trip_id,'manual' FROM exhibitors e
          JOIN trips t ON t.id=e.trip_id WHERE e.trip_id=?''', [trip]);
        await txn.rawInsert('''INSERT OR IGNORE INTO exhibitor_booths
          (participation_id,hall,zone,booth)
          SELECT p.id,e.hall,'',e.booth FROM supplier_participations p
          JOIN exhibitors e ON e.id=p.exhibitor_id WHERE p.trip_id=?
          AND NOT EXISTS(SELECT 1 FROM exhibitor_booths b
            WHERE b.participation_id=p.id)''', [trip]);
      });

  Future<void> selectBooth(String scope, int booth, bool selected) =>
      _write(scope, (txn) async {
        if ((await txn.query('exhibitor_booths', where: 'id=?',
            whereArgs: [booth])).isEmpty) {
          throw StateError('This booth was removed. Refresh the list.');
        }
        final plans = await txn.query('visit_plans', where: 'booth_id=?',
            whereArgs: [booth], orderBy: 'id');
        if (plans.isEmpty) {
          if (selected) {
            await txn.insert('visit_plans',
                {'booth_id': booth, 'selected': 1, 'priority': 1});
          }
        } else {
          await txn.update('visit_plans', {'selected': selected ? 1 : 0},
              where: 'booth_id=?', whereArgs: [booth]);
        }
      });

  Future<void> startVisit(String scope, int booth) =>
      _write(scope, (txn) async {
        final rows = await txn.query('exhibitor_booths',
            where: 'id=?', whereArgs: [booth]);
        if (rows.isEmpty) throw StateError('Booth no longer exists.');
        final owner = Supabase.instance.client.auth.currentUser?.email ?? '';
        final active = await txn.query('visit_sessions',
            where: "status='in_progress' AND (owner_email=? OR booth_id=?)",
            whereArgs: [owner, booth]);
        if (active.isNotEmpty) {
          throw StateError('An active visit already exists for you or this booth. Finish it first.');
        }
        await txn.insert('visit_sessions', {
          'participation_id': rows.first['participation_id'],
          'booth_id': booth,
          'owner_email': owner,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  Future<void> finishVisit(String scope, int visit) =>
      _write(scope, (txn) async {
        final owner = Supabase.instance.client.auth.currentUser?.email ?? '';
        final count = await txn.update('visit_sessions', {
          'status': 'completed',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        }, where: "id=? AND owner_email=? AND status='in_progress'",
            whereArgs: [visit, owner]);
        if (count == 0) throw StateError('Only the visit owner can finish this active visit.');
      });

  Future<List<Map<String, Object?>>> products(String scope, int supplier) async {
    await _check(scope);
    final db = await TradeDatabase.instance.database;
      final rows = await db.rawQuery('''SELECT
          p.id,p.name,p.model_code,p.specs,p.payment_terms,p.quoted_price,
          p.price_currency,p.moq,p.lead_time,p.shortlisted,c.name AS category,
          COUNT(photo.id) AS photo_count
        FROM products p
        LEFT JOIN product_category_assignments a ON a.product_id=p.id
        LEFT JOIN product_categories c ON c.id=a.category_id
        LEFT JOIN attachments photo ON photo.owner_type='product'
          AND photo.owner_id=p.id AND photo.kind='image'
        WHERE p.exhibitor_id=?
        GROUP BY p.id,p.name,p.model_code,p.specs,p.payment_terms,
          p.quoted_price,p.price_currency,p.moq,p.lead_time,p.shortlisted,c.name
        ORDER BY p.name''', [supplier]);
    await _check(scope);
    return rows;
  }

  Future<void> updateProduct({
    required String scope,
    required int supplier,
    required int product,
    required Map<String, String> fields,
    required bool shortlisted,
  }) => _write(scope, (txn) async {
    String value(String key) => fields[key]?.trim() ?? '';
    final name = value('name');
    final categoryName = value('category').replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || categoryName.isEmpty || categoryName.length > 100) {
      throw const FormatException('Product name and category are required.');
    }
    double? number(String key) {
      if (value(key).isEmpty) return null;
      final parsed = double.tryParse(value(key));
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Enter a valid non-negative $key.');
      }
      return parsed;
    }

    final modelCode = value('model_code');
    final duplicate = await txn.query('products',
        columns: const ['id'],
        where: '''exhibitor_id = ? AND id <> ?
            AND lower(trim(name)) = ?
            AND lower(trim(coalesce(model_code, ''))) = ?''',
        whereArgs: [supplier, product, name.toLowerCase(), modelCode.toLowerCase()],
        limit: 1);
    if (duplicate.isNotEmpty) {
      throw StateError(
          'This supplier already has "$name" with the same model/SKU. Keep the existing product instead of creating a duplicate.');
    }

    final categories = await txn.query('product_categories',
        where: 'normalized_name=?', whereArgs: [categoryName.toLowerCase()]);
    if (categories.isNotEmpty && categories.first['archived'] == 1) {
      throw StateError('This category is archived. Choose another.');
    }
    final category = categories.isEmpty
        ? await txn.insert('product_categories', {
            'name': categoryName,
            'normalized_name': categoryName.toLowerCase(),
          })
        : categories.first['id'] as int;
    final changed = await txn.update('products', {
      'name': name,
      'model_code': modelCode,
      'specs': value('specs'),
      'quoted_price': number('quoted_price'),
      'price_currency': value('price_currency').toUpperCase(),
      'moq': number('moq'),
      'lead_time': value('lead_time'),
      'payment_terms': value('payment_terms'),
      'shortlisted': shortlisted ? 1 : 0,
    }, where: 'id=? AND exhibitor_id=?', whereArgs: [product, supplier]);
    if (changed == 0) throw StateError('Product was removed. Refresh and try again.');
    final assigned = await txn.update('product_category_assignments',
        {'category_id': category}, where: 'product_id=?', whereArgs: [product]);
    if (assigned == 0) {
      await txn.insert('product_category_assignments',
          {'product_id': product, 'category_id': category});
    }
  });

  Future<List<Map<String, Object?>>> categories(String scope) async {
    await _check(scope);
    final db = await TradeDatabase.instance.database;
    final rows = await db.query('product_categories',
        where: 'archived=0', orderBy: 'name');
    await _check(scope);
    return rows;
  }

  Future<String> createCategory(String scope, String name) =>
      _write(scope, (txn) async {
        final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (clean.isEmpty || clean.length > 100) {
          throw const FormatException('Enter a category name of 1 to 100 characters.');
        }
        final matches = await txn.query('product_categories',
            where: 'normalized_name=?', whereArgs: [clean.toLowerCase()]);
        if (matches.isNotEmpty) {
          if (matches.first['archived'] == 1) {
            throw StateError('This category is archived. Ask an administrator to restore it.');
          }
          return matches.first['name'] as String;
        }
        await txn.insert('product_categories', {
          'name': clean,
          'normalized_name': clean.toLowerCase(),
        });
        return clean;
      });

  Future<void> categorize(String scope, int product, String name) =>
      _write(scope, (txn) async {
        final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (clean.isEmpty || clean.length > 100) {
          throw const FormatException('Enter a category name of 1 to 100 characters.');
        }
        if ((await txn.query('products', where: 'id=?',
            whereArgs: [product])).isEmpty) {
          throw StateError('Product was removed.');
        }
        final matches = await txn.query('product_categories',
            where: 'normalized_name=?', whereArgs: [clean.toLowerCase()]);
        if (matches.isNotEmpty && matches.first['archived'] == 1) {
          throw StateError('This category is archived. Choose another category.');
        }
        final category = matches.isEmpty
            ? await txn.insert('product_categories',
                {'name': clean, 'normalized_name': clean.toLowerCase()})
            : matches.first['id'] as int;
        final updated = await txn.update('product_category_assignments',
            {'category_id': category}, where: 'product_id=?', whereArgs: [product]);
        if (updated == 0) {
          await txn.insert('product_category_assignments',
              {'product_id': product, 'category_id': category});
        }
      });
}
