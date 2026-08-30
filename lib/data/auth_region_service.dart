import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthRegionService {
  static const _key = 'auth_region';
  final _storage = const FlutterSecureStorage();
  Future<String?> load() => _storage.read(key: _key);
  Future<void> save(String value) => _storage.write(key: _key, value: value);
}
