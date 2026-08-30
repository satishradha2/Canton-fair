import 'package:flutter/material.dart';
import '../data/cloud_api_service.dart';

class TeamSetupScreen extends StatefulWidget {
  const TeamSetupScreen({super.key});
  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends State<TeamSetupScreen> {
  final _api = CloudApiService();
  late Future<List<CloudTeam>> _teams = _api.teams();
  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Create team'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Team name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(c, controller.text),
                      child: const Text('Create'))
                ]));
    if (name?.trim().isEmpty ?? true) return;
    await _api.createTeam(name!.trim());
    if (mounted) setState(() => _teams = _api.teams());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Cloud team')),
      body: FutureBuilder<List<CloudTeam>>(
          future: _teams,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          '${snapshot.error}\n\nBuild with --dart-define=API_BASE_URL=https://your-api.example.com')));
            final teams = snapshot.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'Choose the team whose shared supplier data you want to use.'),
              const SizedBox(height: 12),
              ...teams.map((team) => ListTile(
                  title: Text(team.name),
                  subtitle: Text(team.role),
                  leading: const Icon(Icons.groups),
                  onTap: () => Navigator.pop(context, team))),
              OutlinedButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create team'))
            ]);
          }));
}
