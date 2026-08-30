import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  static const _pinKey = 'app_lock_pin_hash';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> get isEnabled async =>
      (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: _hash(pin));
  }

  Future<bool> verifyPin(String pin) async {
    final saved = await _storage.read(key: _pinKey);
    return saved != null && saved == _hash(pin);
  }

  Future<void> disable() => _storage.delete(key: _pinKey);

  Future<bool> get canUseBiometrics async {
    try {
      return await _localAuth.canCheckBiometrics &&
          (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Canton Fair CRM',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
}
