import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'approval_policy.dart';
import 'database.dart';
import 'product_capture_service.dart';
import 'team_workspace_service.dart';

class CompanyVisitService {
  static const format = 'fair-expert-company-visit-v1';
  static const statuses = ['Tentative', 'Confirmed', 'In progress', 'Completed', 'Cancelled'];
  static List<String> timeZones() { zones.initializeTimeZones(); return tz.timeZoneDatabase.locations.keys.toList()..sort(); }
  static DateTime instant(String wallTime, String zone) {
    zones.initializeTimeZones();
    final date = DateTime.parse(wallTime);
    final result = tz.TZDateTime(tz.getLocation(zone), date.year, date.month, date.day, date.hour, date.minute);
    if (result.hour != date.hour || result.day != date.day) throw StateError('That time does not exist in this time zone. Choose another time.');
    return result.toUtc();
  }
  static Map<String, dynamic> details(Map<String, Object?> row) => ApprovalPolicy.jsonObject(row['commitments_json']);
  static Future<List<Map<String, Object?>>> list(String scope, {int? company}) async {
    await ProductCaptureService.checkScope(scope);
    final db = await TradeDatabase.instance.database;
    final rows = await db.rawQuery('''SELECT m.*,e.name AS company_name FROM meetings m
      JOIN exhibitors e ON e.id=m.exhibitor_id ${company == null ? '' : 'WHERE m.exhibitor_id=?'} ORDER BY m.meeting_date''', company == null ? [] : [company]);
    return rows.where((row) => details(row)['format'] == format).toList();
  }
  static Future<Map<String, Object?>> save(String scope, int company, int? id,
      Map<String, dynamic> data, int expectedRevision) => TeamWorkspaceService.exclusive(() async {
    await ProductCaptureService.checkScope(scope);
    if (!await ProductCaptureService.canWrite()) throw StateError('Member or administrator access is required.');
    if (id != null) await ApprovalPolicy.requireRecordEditor('meetings', id);
    if (!['Factory', 'Office'].contains(data['type']) || !statuses.contains(data['status'])) throw StateError('Select a visit type and status.');
    for (final key in ['address', 'purpose', 'wall_time', 'zone', 'contact_name']) {
      if ((data[key] ?? '').toString().trim().isEmpty) throw StateError('Complete the address, purpose, appointment time and contact.');
    }
    final at = instant(data['wall_time'] as String, data['zone'] as String);
    if (int.tryParse(data['duration'].toString()) == null || int.parse(data['duration'].toString()) <= 0) throw StateError('Duration must be a positive number of minutes.');
    if (data['status'] == 'Completed' && (data['outcome'] ?? '').toString().trim().isEmpty) throw StateError('Record a visit outcome before completing it.');
    final db = await TradeDatabase.instance.database;
    return db.transaction((txn) async {
      if ((await txn.query('exhibitors', where: 'id=?', whereArgs: [company])).isEmpty) throw StateError('Company is unavailable.');
      Map<String, Object?> old = {};
      if (id != null) {
        final rows = await txn.query('meetings', where: 'id=? AND exhibitor_id=?', whereArgs: [id, company]);
        if (rows.isEmpty) throw StateError('Appointment is unavailable.');
        old = rows.first;
        if ((details(old)['revision'] ?? 0) != expectedRevision) throw StateError('This appointment changed. Keep your draft, reopen the latest appointment and review before saving.');
      }
      final previous = old.isEmpty ? <String, dynamic>{} : details(old);
      final now = DateTime.now().toUtc().toIso8601String();
      final actor = Supabase.instance.client.auth.currentUser?.email ?? '';
      final next = {...previous, ...data, 'format': format, 'revision': expectedRevision + 1,
        'created_at': previous['created_at'] ?? now, 'created_by': previous['created_by'] ?? actor,
        'updated_at': now, 'updated_by': actor,
        if (data['status'] == 'In progress' && previous['started_at'] == null) 'started_at': now,
        if (data['status'] == 'Completed' && previous['completed_at'] == null) 'completed_at': now};
      final values = <String, Object?>{'exhibitor_id': company, 'meeting_date': at.toIso8601String(),
        'outcome': data['outcome']?.toString() ?? '', 'notes': data['discussion']?.toString() ?? '',
        'completed': data['status'] == 'Completed' ? 1 : 0, 'commitments_json': jsonEncode(next),
        'assignee_email': actor};
      final savedId = id ?? await txn.insert('meetings', values);
      if (id != null) await txn.update('meetings', values, where: 'id=?', whereArgs: [id]);
      return {...old, ...values, 'id': savedId};
    });
  });
  static Future<File> _draftFile(String scope, String key) async {
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(key)) throw StateError('Invalid visit identifier.');
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/company_visit_drafts/$scope/$key.json');
  }
  static Future<void> draft(String scope, String key, Map<String, dynamic> data) async {
    await ProductCaptureService.checkScope(scope);
    final file = await _draftFile(scope, key);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }
  static Future<Map<String, dynamic>?> loadDraft(String scope, String key) async {
    await ProductCaptureService.checkScope(scope);
    final file = await _draftFile(scope, key);
    return await file.exists() ? ApprovalPolicy.jsonObject(await file.readAsString()) : null;
  }
  static Future<List<Map<String, dynamic>>> unfinished(String scope, int company) async {
    await ProductCaptureService.checkScope(scope);
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/company_visit_drafts/$scope');
    if (!await folder.exists()) return [];
    final saved = await list(scope, company: company);
    final savedKeys = saved.map((row) => details(row)['visit_key']).toSet();
    final result = <Map<String, dynamic>>[];
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final data = ApprovalPolicy.jsonObject(await entry.readAsString());
        final key = data['visit_key'];
        if (data['company_id'] != company || data['appointment_id'] != null ||
            data['revision'] != 0 || key is! String || savedKeys.contains(key)) {
          continue;
        }
        if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(key)) continue;
        result.add(data);
      } on FormatException {
        // Keep an unreadable draft untouched; it must not block other drafts.
      }
    }
    await ProductCaptureService.checkScope(scope);
    result.sort((a, b) => a['visit_key'].toString().compareTo(b['visit_key'].toString()));
    return result;
  }
  static Future<void> clearDraft(String scope, String key) async {
    await ProductCaptureService.checkScope(scope);
    final file = await _draftFile(scope, key);
    if (await file.exists()) await file.delete();
  }
  static Future<void> linkProduct(String scope, int company, int product, String visitKey) => TeamWorkspaceService.exclusive(() async {
    await ProductCaptureService.checkScope(scope);
    if (!await ProductCaptureService.canWrite()) throw StateError('Read-only account.');
    await ApprovalPolicy.requireRecordEditor('products', product);
    final db = await TradeDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', where: 'id=? AND exhibitor_id=?', whereArgs: [product, company]);
      if (rows.isEmpty) throw StateError('Product is unavailable.');
      final data = ApprovalPolicy.jsonObject(rows.first['details_json']);
      data['visit_keys'] = {...List<String>.from(data['visit_keys'] as List? ?? []), visitKey}.toList();
      await txn.update('products', {'details_json': jsonEncode(data)}, where: 'id=?', whereArgs: [product]);
    });
  });
}
