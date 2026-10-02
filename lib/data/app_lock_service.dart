import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppLockService {
  static final changes = ValueNotifier<int>(0);
  static const _pinKey = 'app_lock_pin_hash';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  String? get _biometricKey {
    final user = Supabase.instance.client.auth.currentUser?.id;
    return user == null ? null : 'fair_expert_biometric_login_$user';
  }

  Future<bool> get biometricLoginEnabled async {
    final key = _biometricKey;
    return key != null && await _storage.read(key: key) == 'enabled';
  }

  Future<bool> enableBiometricLogin() async {
    final key = _biometricKey;
    if (key == null || !await canUseBiometrics || !await authenticateWithBiometrics()) return false;
    if (key != _biometricKey) return false;
    await _storage.write(key: key, value: 'enabled');
    return true;
  }

  Future<void> disableBiometricLogin() async {
    final key = _biometricKey;
    if (key != null) await _storage.delete(key: key);
  }

  Future<bool> get isEnabled async =>
      (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: _hash(pin));
    changes.value++;
  }

  Future<bool> verifyPin(String pin) async {
    final saved = await _storage.read(key: _pinKey);
    return saved != null && saved == _hash(pin);
  }

  Future<void> disable() async {
    await _storage.delete(key: _pinKey);
    changes.value++;
  }

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
        localizedReason: 'Unlock Fair Expert',
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
