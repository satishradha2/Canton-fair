import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';

/// AI suggestions stay with the source attachment, never overwrite supplier facts.
class VisitAiService {
  Future<List<Map<String, Object?>>> visits(String scope, int trip) async {
    await _check(scope);
    final db = await TradeDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*,e.name AS supplier_name,b.hall,b.booth
      FROM visit_sessions s
      JOIN supplier_participations p ON p.id=s.participation_id
      JOIN exhibitors e ON e.id=p.exhibitor_id
      LEFT JOIN exhibitor_booths b ON b.id=s.booth_id
      WHERE p.trip_id=? ORDER BY s.started_at DESC,s.id DESC
    ''', [trip]);
    await _check(scope);
    return rows;
  }

  Future<void> _check(String scope) async {
    if (scope != await TeamWorkspaceService().scopeKey()) {
      throw StateError('Workspace changed. Reopen this visit.');
    }
  }

  static Map<String, dynamic> metadata(Map<String, Object?> row) {
    try { return Map<String, dynamic>.from(jsonDecode(row['note'] as String) as Map); }
    catch (_) { return {}; }
  }

  Future<List<Map<String, Object?>>> recordings(String scope, int visit) async {
    await _check(scope);
    final db = await TradeDatabase.instance.database;
    final links = await db.query('cloud_links',
      where: "record_type='visit_session' AND local_id=?", whereArgs: [visit]);
    if (links.isEmpty) return [];
    final rows = await db.query('attachments', where: "kind='audio' AND owner_type='exhibitor'",
      orderBy: 'id DESC');
    await _check(scope);
    return rows.where((row) {
      final note = metadata(row);
      return note['format'] == 'canton-visit-audio-v1' &&
        note['visit_record_id'] == links.first['record_id'];
    }).toList();
  }

  Future<void> process(String scope, Map<String, Object?> row,
      {required bool transcribe, required String language}) async {
    await _check(scope);
    await ApprovalPolicy.requireWriter();
    final note = metadata(row);
    if (note['format'] != 'canton-visit-audio-v1') throw StateError('Invalid recording.');
    final Map<String, dynamic> body;
    if (transcribe) {
      final file = File(row['path'] as String);
      if (!await file.exists()) throw StateError('Download the audio through team sync first.');
      final size = await file.length();
      if (size == 0 || size > 4 * 1024 * 1024) {
        throw StateError('This preview accepts audio up to 4 MB per segment. The original is unchanged.');
      }
      body = {'action': 'transcribe', 'audio': base64Encode(await file.readAsBytes())};
    } else {
      final transcript = note['transcription'];
      if (transcript is! Map) throw StateError('Transcribe this recording first.');
      body = {'action': 'analyze', 'transcript': transcript['text'],
        'language': language};
    }
    await _check(scope);
    Map<String, dynamic> data;
    try {
      final response = await Supabase.instance.client.functions.invoke('visit-ai', body: body)
        .timeout(const Duration(seconds: 110));
      data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200 || data['text'] is! String || (data['text'] as String).isEmpty) {
        throw StateError('No complete AI result was returned. Original audio is unchanged.');
      }
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(details is Map && details['error'] is String
        ? details['error'] as String : 'Visit AI is unavailable or has not been deployed.');
    }
    await TeamWorkspaceService.exclusive(() async {
      await _check(scope);
      final db = await TradeDatabase.instance.database;
      await db.transaction((txn) async {
        final current = await txn.query('attachments', where: 'id=?', whereArgs: [row['id']]);
        if (current.isEmpty || current.first['note'] != row['note']) {
          throw StateError('Recording details changed during processing. Reload before retrying.');
        }
        note[transcribe ? 'transcription' : 'analysis'] = {
          ...data, 'created_at': DateTime.now().toUtc().toIso8601String(),
          'review_required': true,
        };
        await txn.update('attachments', {'note': jsonEncode(note)},
          where: 'id=?', whereArgs: [row['id']]);
      });
    });
  }
}
