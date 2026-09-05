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
    try {
      await _workspace.save(TeamWorkspace(id: team.id, name: team.name));
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Workspace not changed: $error')));
      }
    }
  }

  Future<void> _personal() async {
    try {
      await _workspace.usePersonal();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Workspace not changed: $error')));
      }
    }
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

  Future<void> _manageMembers(CloudTeam team) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TeamMembersScreen(team: team, api: _api)));
    if (mounted) setState(() => _teams = _api.teams());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Cloud team'), actions: [
        TextButton(onPressed: _personal, child: const Text('Personal')),
      ]),
      body: FutureBuilder<List<CloudTeam>>(
          future: _teams,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          '${snapshot.error}\n\nCheck your Supabase connection and team setup.')));
            }
            final teams = snapshot.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'Each team has a separate local database. Existing records remain in Personal; they are never automatically uploaded to another team. Use Personal for backup restoration.'),
              const SizedBox(height: 12),
              ...teams.map((team) => ListTile(
                  title: Text(team.name),
                  subtitle: Text(team.role),
                  leading: const Icon(Icons.groups),
                  onTap: () => _select(team),
                  trailing: team.role == 'admin'
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.person_add_alt_1),
                            tooltip: 'Add team member',
                            onPressed: () => _invite(team),
                          ),
                          IconButton(
                            icon: const Icon(Icons.manage_accounts_outlined),
                            tooltip: 'Manage team members',
                            onPressed: () => _manageMembers(team),
                          ),
                        ])
                      : null)),
              OutlinedButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create team'))
            ]);
          }));
}

class TeamMembersScreen extends StatefulWidget {
  final CloudTeam team;
  final CloudApiService api;

  const TeamMembersScreen({super.key, required this.team, required this.api});

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  late Future<List<CloudMember>> _members = widget.api.members(widget.team);

  void _refresh() => setState(() => _members = widget.api.members(widget.team));

  Future<void> _changeRole(CloudMember member, String role) async {
    try {
      await widget.api.changeMemberRole(widget.team, member, role);
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update member: $error')));
      }
    }
  }

  Future<void> _remove(CloudMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('${member.email} will lose access to this team.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.removeMember(widget.team, member);
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove member: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${widget.team.name} members')),
        body: FutureBuilder<List<CloudMember>>(
          future: _members,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry loading members'),
                ),
              );
            }
            final members = snapshot.data ?? const <CloudMember>[];
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = members[index];
                final isCurrentUser = member.userId == widget.api.currentUserId;
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(member.email),
                  subtitle: Text(member.role),
                  trailing: isCurrentUser
                      ? const Text('You')
                      : PopupMenuButton<String>(
                          tooltip: 'Manage member',
                          onSelected: (value) {
                            if (value == 'remove') {
                              _remove(member);
                            } else {
                              _changeRole(member, value);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                                value: 'viewer', child: Text('Set as viewer')),
                            const PopupMenuItem(
                                value: 'member', child: Text('Set as member')),
                            const PopupMenuItem(
                                value: 'admin', child: Text('Set as admin')),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                                value: 'remove', child: Text('Remove member')),
                          ],
                        ),
                );
              },
            );
          },
        ),
      );
}
