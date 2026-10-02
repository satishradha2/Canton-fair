import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_capture_service.dart';
import 'team_workspace_service.dart';

class ProductAiService {
  static const _images = MethodChannel('canton_fair_crm/card_image');
  static String requestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  static Future<Map<String, dynamic>> extract(String scope, List<String> paths,
      List<String> categories, Map<String, dynamic>? cache) async {
    if (paths.isEmpty || paths.length > 6) throw StateError('Choose one to six specification images.');
    await ProductCaptureService.checkScope(scope);
    final pages = <Map<String, dynamic>>[];
    for (var index = 0; index < paths.length; index++) {
      final image = await _images.invokeMethod<String>('upload', {'path': paths[index]}).timeout(const Duration(seconds: 20));
      if (image == null) throw StateError('Could not prepare an image.');
      pages.add({'index': index, 'image': image});
    }
    final fingerprint = sha256.convert(utf8.encode(jsonEncode({'pages': pages, 'categories': categories}))).toString();
    if (cache?['fingerprint'] == fingerprint && cache?['result'] is Map) return cache!;
    await ProductCaptureService.checkScope(scope);
    final team = await TeamWorkspaceService().load();
    try {
      final response = await Supabase.instance.client.functions.invoke('product-ai', body: {
        'request_id': requestId(), 'team_id': team?.id, 'pages': pages, 'categories': categories,
      }).timeout(const Duration(seconds: 95));
      await ProductCaptureService.checkScope(scope);
      final result = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200 || result['error'] != null) throw StateError(result['error']?.toString() ?? 'Extraction did not complete.');
      return {'fingerprint': fingerprint, 'result': result, 'source_paths': paths};
    } on FunctionException catch (error) {
      throw StateError(error.details is Map ? (error.details as Map)['error']?.toString() ?? 'AI service unavailable.' : 'Product AI is not deployed or available. Your draft is saved.');
    }
  }

  /// Applying reviewed suggestions fills blanks and keeps manually entered data.
  static Map<String, String> fillBlanks(Map<String, String> current, Map<String, dynamic> suggested) {
    final result = Map<String, String>.from(current);
    for (final entry in suggested.entries) {
      if ((result[entry.key] ?? '').trim().isEmpty && entry.value is String) result[entry.key] = entry.value as String;
    }
    return result;
  }

  static Map<String, String> applyReviewed(Map<String, String> current,
      Map<String, dynamic> suggested, Set<String> accepted) {
    final result = Map<String, String>.from(current);
    for (final key in accepted) {
      if (suggested[key] is String) result[key] = suggested[key] as String;
    }
    return result;
  }
}
