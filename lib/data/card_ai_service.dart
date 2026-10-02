import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_card_capture.dart';
import 'team_workspace_service.dart';

class CardAiService {
  static const languages = [
    'English',
    'Simplified Chinese',
    'Arabic',
    'Hindi',
    'Spanish',
    'French',
    'German',
    'Portuguese',
    'Japanese',
    'Korean'
  ];
  static const _images = MethodChannel('canton_fair_crm/card_image');

  static Future<Map<String, dynamic>> readPhoto({required String scope,
      required String path, required String text, String? backPath, String backText = ''}) async {
    var expired = false;
    var submitted = false;
    void checkDeadline() {
      if (expired) throw StateError('Card reading deadline exceeded.');
    }
    Future<Map<String, dynamic>> perform() async {
      final workspace = TeamWorkspaceService();
      if (scope != await workspace.scopeKey()) throw StateError('Workspace changed. Reopen the scanner.');
      checkDeadline();
      final team = await workspace.load();
      checkDeadline();
      final pages = <Map<String, Object?>>[];
      for (final page in [
        {'side': 'front', 'path': path, 'text': text},
        if (backPath != null) {'side': 'back', 'path': backPath, 'text': backText},
      ]) {
        checkDeadline();
        final image = await _images.invokeMethod<String>('upload', {'path': page['path']});
        checkDeadline();
        if (image == null || image.isEmpty) throw StateError('Could not prepare the ${page['side']} image.');
        final sourceText = page['text']!;
        pages.add({'side': page['side'], 'text': sourceText.length > 20000 ? sourceText.substring(0, 20000) : sourceText, 'image': image});
      }
      if (scope != await workspace.scopeKey()) throw StateError('Workspace changed. Nothing was uploaded.');
      checkDeadline();
      try {
        submitted = true;
        final response = await Supabase.instance.client.functions.invoke('card-ai', body: {
          'request_id': _requestId(), 'team_id': team?.id,
          'operation': 'extract', 'target_language': 'English', 'consent': true,
          'pages': pages,
        }).timeout(const Duration(seconds: 90));
        checkDeadline();
        if (scope != await workspace.scopeKey()) throw StateError('Workspace changed. Reopen the scanner.');
        final result = Map<String, dynamic>.from(response.data as Map);
        if (response.status != 200 || result['error'] != null || result['fields'] is! Map) {
          throw StateError(result['error']?.toString() ?? 'AI reading did not complete.');
        }
        return result;
      } on FunctionException catch (error) {
        throw StateError(error.details is Map ? (error.details as Map)['error']?.toString() ?? 'AI reading unavailable.' : 'AI reading unavailable. Use offline OCR or manual entry.');
      }
    }
    return perform().timeout(const Duration(seconds: 110), onTimeout: () {
      expired = true;
      throw StateError(submitted ? 'AI reading timed out. It may have incurred usage; no automatic retry was made.' : 'Image preparation timed out. Nothing was uploaded.');
    });
  }

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
    var expired = false;
    var submitted = false;
    void checkDeadline() {
      if (expired) throw StateError('Card reading deadline exceeded.');
    }

    Future<Map<String, dynamic>> perform() async {
      final workspace = TeamWorkspaceService();
      if (await workspace.scopeKey() != draft.scope) {
        throw StateError('Workspace changed. Reopen the draft.');
      }
      checkDeadline();
      final team = await workspace.load();
      checkDeadline();
      final pages = <Map<String, Object?>>[];
      for (final side in ['front', 'back']) {
        if (!draft.sides.containsKey(side)) continue;
        checkDeadline();
        pages.add({
          'side': side,
          'text': translateOnly
              ? draft.translationSource(side)
              : draft.sideText(side),
          if (!translateOnly)
            'image': await _images.invokeMethod<String>(
                'upload', {'path': draft.readingPath(side)}),
        });
        checkDeadline();
      }
      if (await workspace.scopeKey() != draft.scope) {
        throw StateError('Workspace changed. Nothing was uploaded.');
      }
      checkDeadline();
      try {
        submitted = true;
        final response =
            await Supabase.instance.client.functions.invoke('card-ai', body: {
          'request_id': _requestId(),
          'team_id': team?.id,
          'operation': translateOnly ? 'translate' : 'extract',
          'target_language': language,
          'consent': true,
          'pages': pages,
        }).timeout(const Duration(seconds: 90));
        if (await workspace.scopeKey() != draft.scope) {
          throw StateError('Workspace changed. Reopen the original workspace.');
        }
        checkDeadline();
        final data = Map<String, dynamic>.from(response.data as Map);
        if (response.status != 200 || data['error'] != null) {
          throw StateError('Cloud service could not complete this card.');
        }
        return data;
      } on FunctionException catch (error) {
        final details = error.details;
        throw StateError(details is Map && details['error'] is String
            ? details['error'] as String
            : 'Cloud card reading is not deployed or available. Offline OCR remains available.');
      } on TimeoutException {
        throw StateError(
            'Cloud reading timed out. It may have incurred usage; no automatic retry was made.');
      }
    }

    // Covers workspace access and native image preparation as well as HTTP.
    // A timed-out native call may complete later; deadline checks prevent it
    // from starting a cloud upload after the caller has already stopped waiting.
    return perform().timeout(const Duration(seconds: 110), onTimeout: () {
      expired = true;
      throw StateError(submitted
          ? 'Cloud reading timed out. It may have incurred usage; no automatic retry was made.'
          : 'Preparing the card timed out. Nothing was uploaded. Your original images are preserved.');
    });
  }
}
