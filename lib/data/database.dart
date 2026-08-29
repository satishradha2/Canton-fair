import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import '../models/models.dart';

class TradeDatabase {
  static final TradeDatabase instance = TradeDatabase._();
  static Database? _db;

  TradeDatabase._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'canton_fair_crm.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE trips(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          start_date TEXT,
          end_date TEXT,
          city TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT ''
        );
        ''');
        await db.execute('''
        CREATE TABLE exhibitors(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          booth TEXT NOT NULL DEFAULT '',
          hall TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT '',
          country TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          shortlisted INTEGER NOT NULL DEFAULT 0,
          rating INTEGER NOT NULL DEFAULT 0,
          tags_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute('''
        CREATE TABLE contacts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exhibitor_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          designation TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          whatsapp TEXT NOT NULL DEFAULT '',
          wechat TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute('''
        CREATE TABLE products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exhibitor_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          model_code TEXT NOT NULL DEFAULT '',
          specs TEXT NOT NULL DEFAULT '',
          moq REAL,
          quoted_price REAL,
          price_currency TEXT NOT NULL DEFAULT 'USD',
          lead_time TEXT NOT NULL DEFAULT '',
          payment_terms TEXT NOT NULL DEFAULT '',
          shortlisted INTEGER NOT NULL DEFAULT 0,
          rating INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute('''
        CREATE TABLE meetings(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exhibitor_id INTEGER NOT NULL,
          product_id INTEGER,
          meeting_date TEXT NOT NULL,
          follow_up_date TEXT,
          outcome TEXT NOT NULL DEFAULT 'Interested',
          priority TEXT NOT NULL DEFAULT 'Medium',
          notes TEXT NOT NULL DEFAULT '',
          completed INTEGER NOT NULL DEFAULT 0
        );
        ''');
        await db.execute('''
        CREATE TABLE quotes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          label TEXT NOT NULL,
          unit_price REAL,
          currency TEXT NOT NULL DEFAULT 'USD',
          moq REAL,
          note TEXT NOT NULL DEFAULT '',
          valid_until TEXT,
          is_sample_quote INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db
            .execute('CREATE INDEX idx_exhibitor_trip ON exhibitors(trip_id);');
        await db.execute('''
        CREATE TABLE attachments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          owner_type TEXT NOT NULL,
          owner_id INTEGER NOT NULL,
          kind TEXT NOT NULL DEFAULT 'image',
          path TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute(
            'CREATE INDEX idx_attachment_owner ON attachments(owner_type, owner_id);');
      },
    );
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    final db = await database;
    return db.insert(table, values);
  }

  Future<int> update(String table, int id, Map<String, Object?> values) async {
    final db = await database;
    return db.update(table, values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateWhere(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> deleteWhere(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> _ensureTripCloseoutTable(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS trip_closeouts(trip_id INTEGER PRIMARY KEY, closed_at TEXT NOT NULL, note TEXT NOT NULL)',
    );
  }

  Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final db = await database;
    return db.query(table,
        where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<List<Trip>> getTrips() async {
    final rows = await queryAll('trips', orderBy: 'start_date DESC');
    return rows.map((e) => Trip.fromMap(e)).toList();
  }

  Future<Trip?> getTripById(int id) async {
    final rows = await queryAll('trips',
        where: 'id = ?', whereArgs: [id], orderBy: 'id DESC');
    if (rows.isEmpty) return null;
    return Trip.fromMap(rows.first);
  }

  Future<Trip> insertTrip(Trip t) async {
    final id = await insert('trips', t.toMap()..remove('id'));
    final fresh = await (await database)
        .query('trips', where: 'id = ?', whereArgs: [id], limit: 1);
    return Trip.fromMap(fresh.first);
  }

  Future<void> upsertExhibitor(Exhibitor e) async {
    if (e.id == null) {
      await insert('exhibitors', e.toMap()..remove('id'));
    } else {
      await update('exhibitors', e.id!, e.toMap()..remove('id'));
    }
  }

  Future<int> insertExhibitor(Exhibitor e) async {
    return insert('exhibitors', e.toMap()..remove('id'));
  }

  Future<List<Exhibitor>> getExhibitors(int? tripId) async {
    final rows = await queryAll(
      'exhibitors',
      where: tripId == null ? null : 'trip_id = ?',
      whereArgs: tripId == null ? null : [tripId],
      orderBy: 'name ASC',
    );
    return rows.map((e) => Exhibitor.fromMap(e)).toList();
  }

  Future<List<Contact>> getContacts(int exhibitorId) async {
    final rows = await queryAll(
      'contacts',
      where: 'exhibitor_id = ?',
      whereArgs: [exhibitorId],
      orderBy: 'name ASC',
    );
    return rows.map((e) => Contact.fromMap(e)).toList();
  }

  Future<List<Product>> getProducts(int exhibitorId) async {
    final rows = await queryAll(
      'products',
      where: 'exhibitor_id = ?',
      whereArgs: [exhibitorId],
      orderBy: 'name ASC',
    );
    return rows.map((e) => Product.fromMap(e)).toList();
  }

  Future<List<Product>> getShortlistedProducts() async {
    final rows = await queryAll('products',
        where: 'shortlisted = 1', orderBy: 'rating DESC');
    return rows.map((e) => Product.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getShortlistedProductsWithTrip() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        p.id,
        p.exhibitor_id,
        p.name,
        p.model_code,
        p.specs,
        p.moq,
        p.quoted_price,
        p.price_currency,
        p.lead_time,
        p.payment_terms,
        p.rating,
        e.trip_id,
        e.name AS exhibitor_name,
        t.name AS trip_name,
        t.start_date AS trip_start_date,
        t.end_date AS trip_end_date
      FROM products p
      INNER JOIN exhibitors e ON e.id = p.exhibitor_id
      LEFT JOIN trips t ON t.id = e.trip_id
      WHERE p.shortlisted = 1
      ORDER BY e.trip_id, p.rating DESC, p.id ASC
    ''');
  }

  Future<List<Meeting>> getDueFollowUps() async {
    final rows = await queryAll(
      'meetings',
      where: 'follow_up_date IS NOT NULL',
      orderBy: 'follow_up_date ASC',
    );
    return rows.map((e) => Meeting.fromMap(e)).toList();
  }

  Future<List<Meeting>> getMeetings({int? exhibitorId}) async {
    final rows = await queryAll(
      'meetings',
      where: exhibitorId == null ? null : 'exhibitor_id = ?',
      whereArgs: exhibitorId == null ? null : [exhibitorId],
      orderBy: 'meeting_date DESC',
    );
    return rows.map((e) => Meeting.fromMap(e)).toList();
  }

  Future<List<Quote>> getQuotes(int productId) async {
    final rows = await queryAll(
      'quotes',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return rows.map((e) => Quote.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachments(String ownerType, int ownerId) async {
    final rows = await queryAll(
      'attachments',
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'created_at DESC',
    );
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getTripCloseoutSummaries() async {
    final db = await database;
    await _ensureTripCloseoutTable(db);
    return db.rawQuery('''
      SELECT
        t.id AS trip_id,
        t.name AS trip_name,
        t.start_date,
        t.end_date,
        COALESCE(tc.closed_at, '') AS closed_at,
        COALESCE(tc.note, '') AS close_note,
        COUNT(DISTINCT e.id) AS exhibitor_count,
        COUNT(DISTINCT p.id) AS product_count,
        COUNT(DISTINCT c.id) AS contact_count,
        COUNT(CASE WHEN e.shortlisted = 1 THEN 1 END) AS shortlisted_exhibitor_count,
        COUNT(CASE WHEN p.shortlisted = 1 THEN 1 END) AS shortlisted_product_count,
        COUNT(DISTINCT m.id) AS meeting_count
      FROM trips t
      LEFT JOIN exhibitors e ON e.trip_id = t.id
      LEFT JOIN products p ON p.exhibitor_id = e.id
      LEFT JOIN contacts c ON c.exhibitor_id = e.id
      LEFT JOIN meetings m ON m.exhibitor_id = e.id
      LEFT JOIN trip_closeouts tc ON tc.trip_id = t.id
      GROUP BY t.id, t.name, t.start_date, t.end_date, tc.closed_at, tc.note
      ORDER BY COALESCE(t.start_date, '0000-00-00') DESC
    ''');
  }

  Future<void> closeTrip(int tripId, {String note = ''}) async {
    final db = await database;
    await _ensureTripCloseoutTable(db);
    await db.insert(
      'trip_closeouts',
      {
        'trip_id': tripId,
        'closed_at': DateTime.now().toIso8601String(),
        'note': note
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteExhibitorCascade(int exhibitorId) async {
    final db = await database;
    await db.transaction((txn) async {
      final productRows = await txn.query('products',
          where: 'exhibitor_id = ?', whereArgs: [exhibitorId]);
      final productIds = productRows.map((p) => p['id'] as int).toList();

      final productAttachmentRows = productIds.isEmpty
          ? <Map<String, Object?>>[]
          : await txn.query(
              'attachments',
              where:
                  'owner_type = ? AND owner_id IN (${List.filled(productIds.length, '?').join(',')})',
              whereArgs: ['product', ...productIds],
            );

      final exhibitorAttachmentRows = await txn.query(
        'attachments',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: ['exhibitor', exhibitorId],
      );

      if (productIds.isNotEmpty) {
        final productPlaceholder =
            List.filled(productIds.length, '?').join(',');
        await txn.delete(
          'quotes',
          where: 'product_id IN ($productPlaceholder)',
          whereArgs: productIds,
        );
        await txn.delete(
          'attachments',
          where: 'owner_type = ? AND owner_id IN ($productPlaceholder)',
          whereArgs: ['product', ...productIds],
        );
        await txn.delete('products',
            where: 'exhibitor_id = ?', whereArgs: [exhibitorId]);
      }

      await txn.delete('contacts',
          where: 'exhibitor_id = ?', whereArgs: [exhibitorId]);
      await txn.delete('meetings',
          where: 'exhibitor_id = ?', whereArgs: [exhibitorId]);
      await txn.delete('attachments',
          where: 'owner_type = ? AND owner_id = ?',
          whereArgs: ['exhibitor', exhibitorId]);
      await txn.delete('exhibitors', where: 'id = ?', whereArgs: [exhibitorId]);

      for (final attachment in [
        ...productAttachmentRows,
        ...exhibitorAttachmentRows
      ]) {
        final path = attachment['path'] as String?;
        if (path == null) continue;
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    });
  }

  Future<void> mergeExhibitorRecords(
      int targetExhibitorId, int sourceExhibitorId) async {
    if (targetExhibitorId == sourceExhibitorId) return;
    final db = await database;
    await db.transaction((txn) async {
      final target = await txn.query('exhibitors',
          where: 'id = ?', whereArgs: [targetExhibitorId], limit: 1);
      final source = await txn.query('exhibitors',
          where: 'id = ?', whereArgs: [sourceExhibitorId], limit: 1);
      if (target.isEmpty || source.isEmpty) return;

      await txn.update(
        'contacts',
        {'exhibitor_id': targetExhibitorId},
        where: 'exhibitor_id = ?',
        whereArgs: [sourceExhibitorId],
      );

      await txn.update(
        'meetings',
        {'exhibitor_id': targetExhibitorId},
        where: 'exhibitor_id = ?',
        whereArgs: [sourceExhibitorId],
      );

      await txn.update(
        'attachments',
        {'owner_id': targetExhibitorId},
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: ['exhibitor', sourceExhibitorId],
      );

      final sourceProducts = await txn.query('products',
          where: 'exhibitor_id = ?', whereArgs: [sourceExhibitorId]);
      for (final sourceProductMap in sourceProducts) {
        final sourceProductId = sourceProductMap['id'] as int;
        final sourceProduct = Product.fromMap(sourceProductMap);

        final existing = await txn.query(
          'products',
          where: 'exhibitor_id = ? AND name = ? AND model_code = ?',
          whereArgs: [
            targetExhibitorId,
            sourceProduct.name,
            sourceProduct.modelCode
          ],
          limit: 1,
        );

        int targetProductId;
        if (existing.isNotEmpty) {
          targetProductId = existing.first['id'] as int;
        } else {
          final copied = Map<String, Object?>.from(sourceProduct.toMap())
            ..remove('id')
            ..['exhibitor_id'] = targetExhibitorId;
          targetProductId = await txn.insert('products', copied);
        }

        await txn.update(
          'quotes',
          {'product_id': targetProductId},
          where: 'product_id = ?',
          whereArgs: [sourceProductId],
        );

        await txn.update(
          'attachments',
          {'owner_id': targetProductId},
          where: 'owner_type = ? AND owner_id = ?',
          whereArgs: ['product', sourceProductId],
        );

        await txn
            .delete('products', where: 'id = ?', whereArgs: [sourceProductId]);
      }

      await txn.delete('exhibitors',
          where: 'id = ?', whereArgs: [sourceExhibitorId]);
    });
  }

  Future<void> deleteTripCascade(int tripId) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureTripCloseoutTable(txn);
      final exhibitors = await txn
          .query('exhibitors', where: 'trip_id = ?', whereArgs: [tripId]);
      final exhibitorIds = exhibitors.map((e) => e['id'] as int).toList();
      if (exhibitorIds.isEmpty) {
        await txn.delete('trips', where: 'id = ?', whereArgs: [tripId]);
        await txn.delete('trip_closeouts',
            where: 'trip_id = ?', whereArgs: [tripId]);
        return;
      }

      final placeholders = List.filled(exhibitorIds.length, '?').join(',');

      final productRows = await txn.query(
        'products',
        where: 'exhibitor_id IN ($placeholders)',
        whereArgs: exhibitorIds,
      );
      final productIds = productRows.map((p) => p['id'] as int).toList();
      final productAttachmentRows = productIds.isEmpty
          ? <Map<String, Object?>>[]
          : await txn.query(
              'attachments',
              where:
                  'owner_type = ? AND owner_id IN (${List.filled(productIds.length, '?').join(',')})',
              whereArgs: ['product', ...productIds],
            );

      final attachmentRows = await txn.query(
        'attachments',
        where: 'owner_type = ? AND owner_id IN ($placeholders)',
        whereArgs: ['exhibitor', ...exhibitorIds],
      );

      await txn.delete(
        'contacts',
        where: 'exhibitor_id IN ($placeholders)',
        whereArgs: exhibitorIds,
      );

      if (productIds.isNotEmpty) {
        final productPlaceholder =
            List.filled(productIds.length, '?').join(',');
        await txn.delete(
          'quotes',
          where: 'product_id IN ($productPlaceholder)',
          whereArgs: productIds,
        );

        await txn.delete(
          'attachments',
          where: 'owner_type = ? AND owner_id IN ($productPlaceholder)',
          whereArgs: ['product', ...productIds],
        );

        await txn.delete(
          'products',
          where: 'id IN ($productPlaceholder)',
          whereArgs: productIds,
        );
      }

      await txn.delete(
        'meetings',
        where: 'exhibitor_id IN ($placeholders)',
        whereArgs: exhibitorIds,
      );

      await txn.delete(
        'attachments',
        where: 'owner_type = ? AND owner_id IN ($placeholders)',
        whereArgs: ['exhibitor', ...exhibitorIds],
      );

      await txn.delete('exhibitors', where: 'trip_id = ?', whereArgs: [tripId]);
      await txn
          .delete('trip_closeouts', where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('trips', where: 'id = ?', whereArgs: [tripId]);

      final attachmentsToDelete = [...attachmentRows, ...productAttachmentRows];
      for (final attachment in attachmentsToDelete) {
        final path = attachment['path'] as String?;
        if (path == null) continue;
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    });
  }

  Future<int> addAttachment(Attachment a) async {
    return insert('attachments', a.toMap()..remove('id'));
  }

  Future<int> deleteAttachment(int id) async {
    return delete('attachments', id);
  }

  Future<List<Exhibitor>> searchExhibitors(String query) async {
    final q = '%${query.toLowerCase()}%';
    final rows = await queryAll(
      'exhibitors',
      where:
          'LOWER(name) LIKE ? OR LOWER(booth) LIKE ? OR LOWER(country) LIKE ? OR LOWER(category) LIKE ?',
      whereArgs: [q, q, q, q],
      orderBy: 'name ASC',
    );
    return rows.map((e) => Exhibitor.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getStats() async {
    final db = await database;
    final trips = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM trips')) ??
        0;
    final exhibitors = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM exhibitors')) ??
        0;
    final products = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM products')) ??
        0;
    final shortlistedProducts = Sqflite.firstIntValue(
          await db
              .rawQuery('SELECT COUNT(*) FROM products WHERE shortlisted = 1'),
        ) ??
        0;
    final followUps = Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM meetings WHERE follow_up_date IS NOT NULL'),
        ) ??
        0;
    return [
      {'label': 'Trips', 'value': trips},
      {'label': 'Exhibitors', 'value': exhibitors},
      {'label': 'Products', 'value': products},
      {'label': 'Shortlisted', 'value': shortlistedProducts},
      {'label': 'Pending Follow-ups', 'value': followUps},
    ];
  }
}
