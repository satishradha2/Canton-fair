import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the smallest possible supplier capture safe if field work is interrupted.
class QuickCaptureDraftService {
  static const _key = 'quick_supplier_capture_draft_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, String>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> save(Map<String, String> values) =>
      _storage.write(key: _key, value: jsonEncode(values));

  Future<void> clear() => _storage.delete(key: _key);
}
