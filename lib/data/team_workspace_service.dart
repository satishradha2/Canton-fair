import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamWorkspace {
  final String id;
  final String name;
  const TeamWorkspace({required this.id, required this.name});
}

class TeamWorkspaceService {
  static final changes = ValueNotifier<int>(0);
  static final busy = ValueNotifier<bool>(false);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String get userId {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in before opening a workspace.');
    return id;
  }

  Future<TeamWorkspace?> load() async {
    final raw = await _storage.read(key: 'workspace_v2_$userId');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map;
    return TeamWorkspace(id: data['id'] as String, name: data['name'] as String);
  }

  Future<String> scopeKey() async {
    final user = userId;
    final team = await load();
    if (user != userId) throw StateError('Account changed. Please retry.');
    return sha256.convert(utf8.encode('$user:${team?.id ?? "personal"}')).toString();
  }

  Future<String> databaseName() async {
    final user = userId;
    final team = await load();
    // Keep the original database intact, bound to the upgrading signed-in
    // account's personal workspace. Never attach its unscoped links to a team.
    if (team == null) {
      var owner = await _storage.read(key: 'legacy_database_owner_v2');
      if (owner == null) {
        await _storage.write(key: 'legacy_database_owner_v2', value: user);
        owner = user;
      }
      if (owner == user) return 'canton_fair_crm.db';
    }
    return 'canton_fair_${await scopeKey()}.db';
  }

  Future<void> save(TeamWorkspace workspace) async {
    if (busy.value) throw StateError('Wait for the current data operation.');
    final user = userId;
    final membership = await Supabase.instance.client.from('team_members')
        .select('role').eq('team_id', workspace.id).eq('user_id', user).maybeSingle();
    if (membership == null) throw StateError('You no longer belong to this team.');
    if (user != userId) throw StateError('Account changed. Please retry.');
    await _storage.write(key: 'workspace_v2_$user',
        value: jsonEncode({'id': workspace.id, 'name': workspace.name}));
    changes.value++;
  }

  Future<void> usePersonal() async {
    if (busy.value) throw StateError('Wait for the current data operation.');
    await _storage.delete(key: 'workspace_v2_$userId');
    changes.value++;
  }

  static Future<T> exclusive<T>(Future<T> Function() action) async {
    if (busy.value) throw StateError('Another data operation is already running.');
    busy.value = true;
    try {
      return await action();
    } finally {
      busy.value = false;
    }
  }
}
