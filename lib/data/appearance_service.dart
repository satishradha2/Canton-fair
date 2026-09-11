import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearanceService {
  static const _key = 'appearance_theme_mode';
  static final ValueNotifier<ThemeMode> changes = ValueNotifier(ThemeMode.system);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<ThemeMode> load() async {
    final value = await _storage.read(key: _key);
    final mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    changes.value = mode;
    return mode;
  }

  Future<void> save(ThemeMode mode) async {
    changes.value = mode;
    await _storage.write(key: _key, value: mode.name);
  }
}
