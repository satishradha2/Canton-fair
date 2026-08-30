import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CloudTeam {
  final String id, name, role;
  const CloudTeam({required this.id, required this.name, required this.role});
  factory CloudTeam.fromJson(Map<String, dynamic> json) =>
      CloudTeam(id: json['id'], name: json['name'], role: json['role']);
}

class CloudApiService {
  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Sign in is required.');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json'
    };
  }

  Future<List<CloudTeam>> teams() async {
    if (baseUrl.isEmpty) throw StateError('Cloud API is not configured.');
    final response = await http.get(Uri.parse('$baseUrl/v1/teams'),
        headers: await _headers());
    if (response.statusCode != 200)
      throw StateError('Could not load teams (${response.statusCode}).');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['teams'] as List)
        .map((item) => CloudTeam.fromJson(item))
        .toList();
  }

  Future<CloudTeam> createTeam(String name) async {
    final response = await http.post(Uri.parse('$baseUrl/v1/teams'),
        headers: await _headers(), body: jsonEncode({'name': name}));
    if (response.statusCode != 201)
      throw StateError('Could not create team (${response.statusCode}).');
    return CloudTeam.fromJson(jsonDecode(response.body));
  }
}
