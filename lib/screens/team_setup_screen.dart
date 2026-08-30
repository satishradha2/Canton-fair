import 'package:flutter/material.dart';
import '../data/cloud_api_service.dart';
import '../data/team_workspace_service.dart';

class TeamSetupScreen extends StatefulWidget {
  const TeamSetupScreen({super.key});
  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends State<TeamSetupScreen> {
  final _api = CloudApiService();
  final _workspace = TeamWorkspaceService();
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
    final team = await _api.createTeam(name!.trim());
    await _select(team);
  }

  Future<void> _select(CloudTeam team) async {
    await _workspace.save(TeamWorkspace(id: team.id, name: team.name));
    if (mounted) Navigator.pop(context, team);
  }

  Future<void> _invite(CloudTeam team) async {
    final email = TextEditingController();
    var role = 'member';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add member to ${team.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Registered email'),
            ),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'member', child: Text('Member')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) => setDialogState(() => role = value!),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, {'email': email.text, 'role': role}),
              child: const Text('Add member'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    if (result == null || result['email']!.trim().isEmpty) return;
    try {
      await _api.inviteMember(team, result['email']!, result['role']!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${result['email']} added to ${team.name}.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add member: $error')));
      }
    }
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
                          '${snapshot.error}\n\nCheck your Supabase connection and team setup.')));
            final teams = snapshot.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'Choose the team whose shared supplier data you want to use.'),
              const SizedBox(height: 12),
              ...teams.map((team) => ListTile(
                  title: Text(team.name),
                  subtitle: Text(team.role),
                  leading: const Icon(Icons.groups),
                  onTap: () => _select(team),
                  trailing: team.role == 'admin'
                      ? IconButton(
                          icon: const Icon(Icons.person_add_alt_1),
                          tooltip: 'Add team member',
                          onPressed: () => _invite(team),
                        )
                      : null)),
              OutlinedButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create team'))
            ]);
          }));
}
