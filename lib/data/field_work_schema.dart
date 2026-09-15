import 'package:sqflite/sqflite.dart';
import 'field_work_sync_contract.dart';

/// Additive local foundation. Cloud publication is enabled separately after the
/// matching server protocol and backup contracts are deployed.
class FieldWorkSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS product_categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS supplier_participations(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      exhibitor_id INTEGER NOT NULL,
      trip_id INTEGER NOT NULL,
      organizer_id TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(exhibitor_id, trip_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS exhibitor_booths(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      participation_id INTEGER NOT NULL,
      hall TEXT NOT NULL DEFAULT '',
      zone TEXT NOT NULL DEFAULT '',
      booth TEXT NOT NULL DEFAULT '',
      UNIQUE(participation_id, hall, zone, booth)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS visit_plans(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      booth_id INTEGER NOT NULL,
      priority INTEGER NOT NULL DEFAULT 1 CHECK(priority BETWEEN 0 AND 2),
      assignee_email TEXT NOT NULL DEFAULT '',
      appointment_at TEXT,
      objectives TEXT NOT NULL DEFAULT '',
      selected INTEGER NOT NULL DEFAULT 1 CHECK(selected IN (0,1)),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS visit_sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      participation_id INTEGER NOT NULL,
      booth_id INTEGER,
      plan_id INTEGER,
      owner_email TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress','completed','cancelled')),
      started_at TEXT NOT NULL,
      ended_at TEXT,
      outcome TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_booth_hall
      ON exhibitor_booths(hall, participation_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_participation_trip
      ON supplier_participations(trip_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_visit_participation
      ON visit_sessions(participation_id, started_at)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS product_category_assignments(
      product_id INTEGER PRIMARY KEY,
      category_id INTEGER NOT NULL
    )''');

    // Preserve existing identities and supplier shortlist meanings. Importing
    // legacy booth context does not imply that a supplier was selected to visit.
    await db.execute('''INSERT OR IGNORE INTO supplier_participations
      (exhibitor_id, trip_id, source)
      SELECT e.id, e.trip_id, 'legacy'
      FROM exhibitors e JOIN trips t ON t.id = e.trip_id''');
    await db.execute('''INSERT OR IGNORE INTO exhibitor_booths
      (participation_id, hall, zone, booth)
      SELECT p.id, e.hall, '', e.booth
      FROM supplier_participations p JOIN exhibitors e ON e.id = p.exhibitor_id
      WHERE p.source = 'legacy' ''');

    await db.execute('''CREATE TRIGGER IF NOT EXISTS field_delete_supplier
      AFTER DELETE ON exhibitors BEGIN
        DELETE FROM supplier_participations WHERE exhibitor_id = OLD.id;
      END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS field_delete_trip
      AFTER DELETE ON trips BEGIN
        DELETE FROM supplier_participations WHERE trip_id = OLD.id;
      END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS field_delete_participation
      AFTER DELETE ON supplier_participations BEGIN
        DELETE FROM visit_sessions WHERE participation_id = OLD.id;
        DELETE FROM visit_plans WHERE booth_id IN
          (SELECT id FROM exhibitor_booths WHERE participation_id = OLD.id);
        DELETE FROM exhibitor_booths WHERE participation_id = OLD.id;
      END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS field_delete_product
      AFTER DELETE ON products BEGIN
        DELETE FROM product_category_assignments WHERE product_id = OLD.id;
      END''');
    for (final entry in FieldWorkSyncContract.tables.entries) {
      final key = FieldWorkSyncContract.primaryKey(entry.key);
      await db.execute('''CREATE TRIGGER IF NOT EXISTS queue_delete_${entry.value}
        AFTER DELETE ON ${entry.value} BEGIN
          INSERT OR IGNORE INTO sync_deletions
            (record_type, local_id, record_id, version)
          SELECT record_type, local_id, record_id, version FROM cloud_links
          WHERE record_type = '${entry.key}' AND local_id = OLD.$key;
        END''');
    }
  }
}
