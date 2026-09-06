import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_card_capture.dart';
import 'team_workspace_service.dart';

class CardAiService {
  static const languages = ['English', 'Simplified Chinese', 'Arabic', 'Hindi',
    'Spanish', 'French', 'German', 'Portuguese', 'Japanese', 'Korean'];
  static const _images = MethodChannel('canton_fair_crm/card_image');

  static String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<Map<String, dynamic>> read(BusinessCardCapture draft,
      {required bool translateOnly, required String language}) async {
    final workspace = TeamWorkspaceService();
    if (await workspace.scopeKey() != draft.scope) throw StateError('Workspace changed. Reopen the draft.');
    final team = await workspace.load();
    final pages = <Map<String, Object?>>[];
    for (final side in ['front', 'back']) {
      if (!draft.sides.containsKey(side)) continue;
      pages.add({
        'side': side, 'text': translateOnly ? draft.translationSource(side) : draft.sideText(side),
        if (!translateOnly) 'image': await _images.invokeMethod<String>('upload', {'path': draft.readingPath(side)}),
      });
    }
    if (await workspace.scopeKey() != draft.scope) throw StateError('Workspace changed. Nothing was uploaded.');
    try {
      final response = await Supabase.instance.client.functions.invoke('card-ai', body: {
        'request_id': _requestId(), 'team_id': team?.id,
        'operation': translateOnly ? 'translate' : 'extract',
        'target_language': language, 'consent': true, 'pages': pages,
      }).timeout(const Duration(seconds: 90));
      if (await workspace.scopeKey() != draft.scope) throw StateError('Workspace changed. Reopen the original workspace.');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200 || data['error'] != null) throw StateError('Cloud service could not complete this card.');
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(details is Map && details['error'] is String
          ? details['error'] as String : 'Cloud card reading is not deployed or available. Offline OCR remains available.');
    } on TimeoutException {
      throw StateError('Cloud reading timed out. It may have incurred usage; no automatic retry was made.');
    }
  }
}
