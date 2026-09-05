import 'package:supabase_flutter/supabase_flutter.dart';

class CloudTeam {
  final String id, name, role;
  const CloudTeam({required this.id, required this.name, required this.role});
  factory CloudTeam.fromJson(Map<String, dynamic> json) =>
      CloudTeam(id: json['id'], name: json['name'], role: json['role']);
}

class CloudMember {
  final String userId;
  final String email;
  final String role;

  const CloudMember({
    required this.userId,
    required this.email,
    required this.role,
  });

  factory CloudMember.fromJson(Map<String, dynamic> json) => CloudMember(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
      );
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
    final row = record is List ? record.single : record;
    return CloudTeam.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> inviteMember(CloudTeam team, String email, String role) async {
    await _client.rpc('invite_team_member', params: {
      'target_team': team.id,
      'member_email': email.trim(),
      'member_role': role,
    });
  }

  Future<List<CloudMember>> members(CloudTeam team) async {
    final records = await _client.rpc('list_team_members', params: {
      'target_team': team.id,
    });
    return (records as List)
        .map((record) =>
            CloudMember.fromJson(Map<String, dynamic>.from(record as Map)))
        .toList();
  }

  Future<void> changeMemberRole(
      CloudTeam team, CloudMember member, String role) async {
    await _client.rpc('update_team_member_role', params: {
      'target_team': team.id,
      'target_user': member.userId,
      'member_role': role,
    });
  }

  Future<void> removeMember(CloudTeam team, CloudMember member) async {
    await _client.rpc('remove_team_member', params: {
      'target_team': team.id,
      'target_user': member.userId,
    });
  }

  String? get currentUserId => _client.auth.currentUser?.id;
}
