import 'dart:convert';
import '../models/models.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class FairCaptureService {
  static const hallMarker = '\n\n[fair-expert-halls]';

  static List<String> halls(Trip fair) {
    final index = fair.notes.indexOf(hallMarker);
    if (index < 0) return [];
    try {
      return (jsonDecode(fair.notes.substring(index + hallMarker.length)) as List)
          .whereType<String>().where((name) => name.trim().isNotEmpty).toSet().toList();
    } catch (_) { return []; }
  }

  static Future<List<Trip>> fairs() async =>
      (await TradeDatabase.instance.getTrips())
          .where((fair) => fair.name != 'Fair Expert contacts').toList();

  static Future<bool> hasLocation(int companyId, int fairId) async {
    final db = await TradeDatabase.instance.database;
    final rows = await db.rawQuery('''SELECT b.id FROM exhibitor_booths b
      JOIN supplier_participations p ON p.id=b.participation_id
      WHERE p.exhibitor_id=? AND p.trip_id=?
      AND trim(b.hall)<>'' AND trim(b.booth)<>'' LIMIT 1''', [companyId, fairId]);
    return rows.isNotEmpty;
  }

  static Future<int> save({required String scope, required Trip fair,
    required Exhibitor company, required Contact contact,
    String? hall, String? booth}) => TeamWorkspaceService.exclusive(() async {
    await ApprovalPolicy.requireWriter();
    if (await TeamWorkspaceService().scopeKey() != scope) {
      throw StateError('Workspace changed. Reopen the scanner.');
    }
    final db = await TradeDatabase.instance.database;
    final canUpdateCompany = company.id == null || await ApprovalPolicy.canEditRecord('exhibitors', company.id!);
    return db.transaction((txn) async {
      final fairRows = await txn.query('trips', where: 'id=?', whereArgs: [fair.id]);
      if (fairRows.isEmpty) throw StateError('Select an available fair.');
      final currentFair = Trip.fromMap(fairRows.first);
      var companyId = company.id;
      if (companyId == null) {
        companyId = await txn.insert('exhibitors', company.toMap()..remove('id'));
      } else if ((await txn.query('exhibitors', where: 'id=?', whereArgs: [companyId])).isEmpty) {
        throw StateError('Company was removed. Please retry.');
      }
      final participation = await txn.query('supplier_participations',
          where: 'exhibitor_id=? AND trip_id=?', whereArgs: [companyId, fair.id]);
      final participationId = participation.isEmpty
          ? await txn.insert('supplier_participations', {'exhibitor_id': companyId, 'trip_id': fair.id, 'source': 'ocr'})
          : participation.first['id'] as int;
      final locations = await txn.query('exhibitor_booths',
          where: "participation_id=? AND trim(hall)<>'' AND trim(booth)<>''", whereArgs: [participationId]);
      if (locations.isEmpty) {
        if (hall == null || !halls(currentFair).contains(hall) || booth == null || booth.trim().isEmpty) {
          throw StateError('Select a master hall and enter the booth number.');
        }
        await txn.insert('exhibitor_booths', {'participation_id': participationId, 'hall': hall, 'zone': '', 'booth': booth.trim()});
        if (company.tripId == fair.id && canUpdateCompany) {
          await txn.update('exhibitors', {'hall': hall, 'booth': booth.trim()}, where: 'id=?', whereArgs: [companyId]);
        }
      }
      final contacts = await txn.query('contacts', where: 'exhibitor_id=?', whereArgs: [companyId]);
      final email = contact.email.trim().toLowerCase();
      final phone = contact.phone.replaceAll(RegExp(r'\D'), '');
      final duplicate = contacts.any((row) =>
          (email.isNotEmpty && (row['email'] as String? ?? '').trim().toLowerCase() == email) ||
          (phone.isNotEmpty && (row['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '') == phone) ||
          (contact.name != 'Primary contact' && (row['name'] as String? ?? '').trim().toLowerCase() == contact.name.trim().toLowerCase()));
      if (!duplicate) {
        final values = contact.toMap()..remove('id');
        values['exhibitor_id'] = companyId;
        await txn.insert('contacts', values);
      }
      return companyId;
    });
  });
}
