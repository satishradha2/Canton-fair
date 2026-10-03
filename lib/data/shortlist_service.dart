import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class ShortlistService {
  static Map<String, dynamic> metadata(Object? previous, {required bool selected,
    required bool wasSelected, required String reason, required String fair}) {
    final old = ApprovalPolicy.jsonObject(previous);
    final now = DateTime.now().toUtc().toIso8601String();
    final actor = Supabase.instance.client.auth.currentUser?.email ?? '';
    return {...old, 'active': selected, 'reason': reason.trim(),
      if (selected && !wasSelected) 'selected_at': now,
      if (selected && !wasSelected) 'selected_by': actor,
      if (selected && !wasSelected) 'fair': fair,
      'updated_at': now, 'updated_by': actor,
      if (!selected && wasSelected) 'removed_at': now,
      if (!selected && wasSelected) 'removed_by': actor};
  }

  static Future<void> set({required String scope, required int id,
    required bool product, required bool selected, String reason = '', int? fairId}) =>
      TeamWorkspaceService.exclusive(() async {
        if (scope != await TeamWorkspaceService().scopeKey()) throw StateError('Workspace changed. Reopen this page.');
        await ApprovalPolicy.requireWriter();
        await ApprovalPolicy.requireRecordEditor(product ? 'products' : 'exhibitors', id);
        if (scope != await TeamWorkspaceService().scopeKey()) throw StateError('Workspace changed. Reopen this page.');
        final db = await TradeDatabase.instance.database;
        await db.transaction((txn) async {
          final table = product ? 'products' : 'exhibitors';
          final column = product ? 'details_json' : 'field_capture_json';
          final rows = await txn.query(table, where: 'id=?', whereArgs: [id]);
          if (rows.isEmpty) throw StateError('Record no longer available.');
          final row = rows.first;
          final details = ApprovalPolicy.jsonObject(row[column]);
          final fairs = await txn.query('trips', where: 'id=?', whereArgs: [fairId ?? (product ? details['fair_id'] : row['trip_id'])]);
          details['shortlist'] = metadata(details['shortlist'], selected: selected,
            wasSelected: row['shortlisted'] == 1, reason: reason,
            fair: fairs.isEmpty ? (details['fair_name']?.toString() ?? '') : fairs.first['name'].toString());
          await txn.update(table, {'shortlisted': selected ? 1 : 0, column: jsonEncode(details)}, where: 'id=?', whereArgs: [id]);
        });
      });

  static Future<List<Map<String, Object?>>> entries(bool product) async {
    final db = await TradeDatabase.instance.database;
    return product ? db.rawQuery('''SELECT p.*, e.name AS company_name FROM products p
      JOIN exhibitors e ON e.id=p.exhibitor_id WHERE p.shortlisted=1 ORDER BY p.name''') :
      db.query('exhibitors', where: 'shortlisted=1', orderBy: 'name');
  }
}
