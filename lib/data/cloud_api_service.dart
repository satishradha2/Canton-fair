import 'package:supabase_flutter/supabase_flutter.dart';

class CloudTeam {
  final String id, name, role;
  const CloudTeam({required this.id, required this.name, required this.role});
  factory CloudTeam.fromJson(Map<String, dynamic> json) =>
      CloudTeam(id: json['id'], name: json['name'], role: json['role']);
}

class CloudApiService {
  final _client = Supabase.instance.client;

  Future<List<CloudTeam>> teams() async {
    final records = await _client
        .from('team_members')
        .select('role, teams(id, name)')
        .eq('user_id', _client.auth.currentUser!.id);
    return records.map((record) {
      final team = record['teams'] as Map<String, dynamic>;
      return CloudTeam(
        id: team['id'] as String,
        name: team['name'] as String,
        role: record['role'] as String,
      );
    }).toList();
  }

  Future<CloudTeam> createTeam(String name) async {
    final record =
        await _client.rpc('create_team', params: {'team_name': name});
    return CloudTeam.fromJson(Map<String, dynamic>.from(record as Map));
  }

  Future<void> inviteMember(CloudTeam team, String email, String role) async {
    await _client.rpc('invite_team_member', params: {
      'target_team': team.id,
      'member_email': email.trim(),
      'member_role': role,
    });
  }
}
