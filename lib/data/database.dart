import 'dart:convert';

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
      version: 21,
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
          quality_score INTEGER NOT NULL DEFAULT 0,
          response_speed_score INTEGER NOT NULL DEFAULT 0,
          trust_score INTEGER NOT NULL DEFAULT 0,
          moq_fit_score INTEGER NOT NULL DEFAULT 0,
          reliability_score INTEGER NOT NULL DEFAULT 0,
          planned_visit_at TEXT,
          visited_at TEXT,
          decision TEXT NOT NULL DEFAULT 'Maybe',
          decision_reason TEXT NOT NULL DEFAULT '',
          field_capture_json TEXT NOT NULL DEFAULT '{}',
          verification_json TEXT NOT NULL DEFAULT '{}',
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
          profile_json TEXT NOT NULL DEFAULT '{}',
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
          purchase_readiness_json TEXT NOT NULL DEFAULT '{}',
          details_json TEXT NOT NULL DEFAULT '{}',
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
          assignee_email TEXT NOT NULL DEFAULT '',
          commitments_json TEXT NOT NULL DEFAULT '{}',
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
          approval_status TEXT NOT NULL DEFAULT 'Draft',
          approval_comment TEXT NOT NULL DEFAULT '',
          approved_by TEXT NOT NULL DEFAULT '',
          approved_at TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute('''
        CREATE TABLE samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exhibitor_id INTEGER NOT NULL,
          product_id INTEGER,
          requested_at TEXT NOT NULL,
          expected_at TEXT,
          received_at TEXT,
          status TEXT NOT NULL DEFAULT 'Requested',
          courier TEXT NOT NULL DEFAULT '',
          tracking_number TEXT NOT NULL DEFAULT '',
          sample_cost REAL,
          shipping_cost REAL,
          assignee_email TEXT NOT NULL DEFAULT '',
          test_notes TEXT NOT NULL DEFAULT '',
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
          annotations_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ''');
        await db.execute(
            'CREATE INDEX idx_attachment_owner ON attachments(owner_type, owner_id);');
        await _createSavedFiltersTable(db);
        await _createAuditLogsTable(db);
        await _createCloudLinksTable(db);
        await _createCloudSyncConflictsTable(db);
        await _createSourcingBriefsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN quality_score INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN response_speed_score INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN trust_score INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN moq_fit_score INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN reliability_score INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE exhibitors ADD COLUMN planned_visit_at TEXT');
          await db.execute('ALTER TABLE exhibitors ADD COLUMN visited_at TEXT');
        }
        if (oldVersion < 4) {
          await _createSavedFiltersTable(db);
        }
        if (oldVersion < 5) {
          await _createAuditLogsTable(db);
        }
        if (oldVersion < 6) {
          await _createCloudLinksTable(db);
        }
        if (oldVersion < 7) {
          await db.execute(
              "ALTER TABLE cloud_links ADD COLUMN content_hash TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 8) {
          await _createCloudSyncConflictsTable(db);
        }
        if (oldVersion < 9) {
          await db.execute(
              "ALTER TABLE meetings ADD COLUMN assignee_email TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 10) {
          await db.execute(
              "ALTER TABLE exhibitors ADD COLUMN decision TEXT NOT NULL DEFAULT 'Maybe'");
          await db.execute(
              "ALTER TABLE exhibitors ADD COLUMN decision_reason TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 11) {
          await db.execute(
              "ALTER TABLE quotes ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'Draft'");
          await db.execute(
              "ALTER TABLE quotes ADD COLUMN approval_comment TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE quotes ADD COLUMN approved_by TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE quotes ADD COLUMN approved_at TEXT');
        }
        if (oldVersion < 12) {
          await db.execute(
              "ALTER TABLE exhibitors ADD COLUMN field_capture_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 13) {
          await db.execute(
              "ALTER TABLE exhibitors ADD COLUMN verification_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 14) {
          await db.execute('''
            CREATE TABLE samples(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              exhibitor_id INTEGER NOT NULL,
              product_id INTEGER,
              requested_at TEXT NOT NULL,
              expected_at TEXT,
              received_at TEXT,
              status TEXT NOT NULL DEFAULT 'Requested',
              courier TEXT NOT NULL DEFAULT '',
              tracking_number TEXT NOT NULL DEFAULT '',
              sample_cost REAL,
              shipping_cost REAL,
              assignee_email TEXT NOT NULL DEFAULT '',
              test_notes TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
          ''');
        }
        if (oldVersion < 15) {
          await db.execute(
              "ALTER TABLE products ADD COLUMN purchase_readiness_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 16) {
          await db.execute(
              "ALTER TABLE meetings ADD COLUMN commitments_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 17) {
          await db.execute(
              "ALTER TABLE attachments ADD COLUMN annotations_json TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 18) {
          await db.execute(
              "ALTER TABLE audit_logs ADD COLUMN actor_email TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 19) {
          await db.execute(
              "ALTER TABLE products ADD COLUMN details_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 20) {
          await db.execute(
              "ALTER TABLE contacts ADD COLUMN profile_json TEXT NOT NULL DEFAULT '{}'");
        }
        if (oldVersion < 21) {
          await _createSourcingBriefsTable(db);
        }
      },
    );
  }

  Future<void> _createSourcingBriefsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sourcing_briefs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        target_price REAL,
        target_moq REAL,
        required_certifications TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
  }

  Future<void> _createSavedFiltersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_supplier_filters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        query TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        min_rating INTEGER NOT NULL DEFAULT 0,
        shortlist_only INTEGER NOT NULL DEFAULT 0,
        visit_status TEXT NOT NULL DEFAULT 'all',
        min_price REAL,
        max_price REAL,
        min_moq REAL,
        max_moq REAL,
        expiring_quotes_only INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createAuditLogsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        actor_email TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createCloudLinksTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_links(
        record_type TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        record_id TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL DEFAULT '',
        PRIMARY KEY(record_type, local_id),
        UNIQUE(record_type, record_id)
      )
    ''');
  }

  Future<void> _createCloudSyncConflictsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_sync_conflicts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id TEXT NOT NULL,
        record_type TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        record_id TEXT NOT NULL,
        local_payload TEXT NOT NULL,
        remote_payload TEXT NOT NULL,
        remote_version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(team_id, record_type, record_id)
      )
    ''');
  }

  Future<void> saveCloudSyncConflict({
    required String teamId,
    required String recordType,
    required int localId,
    required String recordId,
    required Map<String, Object?> localPayload,
    required Map<String, Object?> remotePayload,
    required int remoteVersion,
  }) async {
    final db = await database;
    await db.insert(
        'cloud_sync_conflicts',
        {
          'team_id': teamId,
          'record_type': recordType,
          'local_id': localId,
          'record_id': recordId,
          'local_payload': jsonEncode(localPayload),
          'remote_payload': jsonEncode(remotePayload),
          'remote_version': remoteVersion,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCloudSyncConflicts() =>
      queryAll('cloud_sync_conflicts', orderBy: 'created_at DESC');

  Future<void> deleteCloudSyncConflict(int id) async {
    final db = await database;
    await db.delete('cloud_sync_conflicts', where: 'id = ?', whereArgs: [id]);
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

  Future<Map<String, dynamic>?> getCloudLink(
      String recordType, int localId) async {
    final db = await database;
    final rows = await db.query('cloud_links',
        where: 'record_type = ? AND local_id = ?',
        whereArgs: [recordType, localId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getCloudLinkByRecordId(
      String recordType, String recordId) async {
    final db = await database;
    final rows = await db.query('cloud_links',
        where: 'record_type = ? AND record_id = ?',
        whereArgs: [recordType, recordId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveCloudLink(
    String recordType,
    int localId,
    String recordId,
    int version, {
    String contentHash = '',
  }) async {
    final db = await database;
    await db.insert(
        'cloud_links',
        {
          'record_type': recordType,
          'local_id': localId,
          'record_id': recordId,
          'version': version,
          'content_hash': contentHash,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<Exhibitor?> getExhibitorById(int id) async {
    final rows = await queryAll('exhibitors', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Exhibitor.fromMap(rows.first);
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

  Future<List<Sample>> getSamples({int? exhibitorId}) async {
    final rows = await queryAll(
      'samples',
      where: exhibitorId == null ? null : 'exhibitor_id = ?',
      whereArgs: exhibitorId == null ? null : [exhibitorId],
      orderBy: 'COALESCE(expected_at, requested_at) ASC',
    );
    return rows.map(Sample.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getQuotesForApproval() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        q.*,
        p.name AS product_name,
        p.model_code AS product_model_code,
        e.name AS supplier_name,
        e.booth AS supplier_booth
      FROM quotes q
      LEFT JOIN products p ON p.id = q.product_id
      LEFT JOIN exhibitors e ON e.id = p.exhibitor_id
      ORDER BY q.created_at DESC
    ''');
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
        'samples',
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

  Future<List<SourcingBrief>> getSourcingBriefs() async {
    final rows = await queryAll('sourcing_briefs', orderBy: 'created_at DESC');
    return rows.map(SourcingBrief.fromMap).toList();
  }

  Future<int> saveSourcingBrief(SourcingBrief brief) =>
      insert('sourcing_briefs', brief.toMap()..remove('id'));

  Future<void> updateSourcingBrief(SourcingBrief brief) =>
      update('sourcing_briefs', brief.id!, brief.toMap()..remove('id'));

  Future<int> deleteSourcingBrief(int id) => delete('sourcing_briefs', id);

  Future<List<Exhibitor>> searchExhibitors(String query) async {
    final q = '%${query.toLowerCase()}%';
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT e.*
      FROM exhibitors e
      LEFT JOIN contacts c ON c.exhibitor_id = e.id
      LEFT JOIN products p ON p.exhibitor_id = e.id
      WHERE LOWER(e.name) LIKE ?
         OR LOWER(e.booth) LIKE ?
         OR LOWER(e.hall) LIKE ?
         OR LOWER(e.country) LIKE ?
         OR LOWER(e.category) LIKE ?
         OR LOWER(e.tags_json) LIKE ?
         OR LOWER(c.name) LIKE ?
         OR LOWER(c.phone) LIKE ?
         OR LOWER(c.email) LIKE ?
         OR LOWER(c.whatsapp) LIKE ?
         OR LOWER(c.wechat) LIKE ?
         OR LOWER(p.name) LIKE ?
         OR LOWER(p.model_code) LIKE ?
         OR LOWER(p.specs) LIKE ?
      ORDER BY e.name ASC
    ''', List.filled(14, q));
    return rows.map((e) => Exhibitor.fromMap(e)).toList();
  }

  Future<List<SavedSupplierFilter>> getSavedSupplierFilters() async {
    final rows = await queryAll('saved_supplier_filters', orderBy: 'name ASC');
    return rows.map(SavedSupplierFilter.fromMap).toList();
  }

  Future<int> saveSupplierFilter(SavedSupplierFilter filter) async {
    return insert('saved_supplier_filters', filter.toMap()..remove('id'));
  }

  Future<int> deleteSavedSupplierFilter(int id) =>
      delete('saved_supplier_filters', id);

  Future<void> logAudit(String action, String details,
      {String actorEmail = ''}) async {
    await insert('audit_logs', {
      'action': action,
      'details': details,
      'actor_email': actorEmail,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 50}) async {
    final db = await database;
    return db.query('audit_logs', orderBy: 'created_at DESC', limit: limit);
  }

  Future<int> replaceWithBackup(
      Map<String, List<Map<String, dynamic>>> tables) async {
    final db = await database;
    const deleteOrder = [
      'attachments',
      'quotes',
      'meetings',
      'contacts',
      'products',
      'exhibitors',
      'trips',
      'saved_supplier_filters',
      'sourcing_briefs',
    ];
    const insertOrder = [
      'trips',
      'exhibitors',
      'contacts',
      'products',
      'meetings',
      'quotes',
      'attachments',
      'saved_supplier_filters',
      'sourcing_briefs',
    ];

    var restored = 0;
    await db.transaction((txn) async {
      for (final table in deleteOrder) {
        await txn.delete(table);
      }
      for (final table in insertOrder) {
        for (final row in tables[table] ?? const []) {
          await txn.insert(table, Map<String, Object?>.from(row));
          restored++;
        }
      }
    });
    return restored;
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
