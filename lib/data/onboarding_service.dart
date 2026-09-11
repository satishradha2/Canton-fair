import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only the user's choice to hide the getting-started guide.
class OnboardingService {
  static const _key = 'onboarding_hidden_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<bool> isHidden() async =>
      (await _storage.read(key: _key)) == 'true';

  Future<void> hide() => _storage.write(key: _key, value: 'true');

  Future<void> show() => _storage.delete(key: _key);
}
