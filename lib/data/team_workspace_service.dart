import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TeamWorkspace {
  final String id;
  final String name;

  const TeamWorkspace({required this.id, required this.name});
}

class TeamWorkspaceService {
  static const _teamIdKey = 'selected_team_id';
  static const _teamNameKey = 'selected_team_name';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<TeamWorkspace?> load() async {
    final id = await _storage.read(key: _teamIdKey);
    final name = await _storage.read(key: _teamNameKey);
    if (id == null || name == null) return null;
    return TeamWorkspace(id: id, name: name);
  }

  Future<void> save(TeamWorkspace workspace) async {
    await _storage.write(key: _teamIdKey, value: workspace.id);
    await _storage.write(key: _teamNameKey, value: workspace.name);
  }
}
