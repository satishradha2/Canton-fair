import 'package:flutter/material.dart';
import '../data/cloud_api_service.dart';
import '../data/team_workspace_service.dart';
import '../widgets/focused_workspace.dart';
import '../widgets/field_workspace.dart';

class TeamSetupScreen extends StatefulWidget {
  const TeamSetupScreen({super.key});
  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends State<TeamSetupScreen> {
  final _api = CloudApiService();
  final _workspace = TeamWorkspaceService();
  late Future<List<CloudTeam>> _teams = _api.teams();
  String? _activeId;
  int _panel = 0;
  @override
  void initState() { super.initState(); _loadActive(); }
  Future<void> _loadActive() async {
    try {
      final active = await _workspace.load();
      if (mounted) setState(() => _activeId = active?.id);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read active workspace: $error')));
    }
  }
  Future<void> _create() async {
    var teamName = '';
    final name = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Create team'),
                content: TextField(
                    onChanged: (value) => teamName = value,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Team name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(c, teamName),
                      child: const Text('Create'))
                ]));
    if (!mounted || (name?.trim().isEmpty ?? true)) return;
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
    var email = '';
    var role = 'member';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add member to ${team.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              onChanged: (value) => email = value,
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
                  Navigator.pop(context, {'email': email.trim(), 'role': role}),
              child: const Text('Add member'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null || result['email']!.trim().isEmpty) return;
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
    if (mounted) {
      setState(() {
        _teams = _api.teams();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Team workspace')),
    body: FutureBuilder<List<CloudTeam>>(future: _teams, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) {
        return Center(child: TextButton.icon(
          onPressed: () => setState(() => _teams = _api.teams()), icon: const Icon(Icons.refresh), label: const Text('Retry loading teams')));
      }
      final teams = snapshot.data ?? <CloudTeam>[];
      CloudTeam? active;
      for (final team in teams) { if (team.id == _activeId) active = team; }
      final current = active;
      return FocusedWorkspace(title: current?.name ?? 'Personal workspace',
        subtitle: current == null ? 'Select a team in Workspace settings to share saved records.' : 'Active team / ${current.role} access',
        index: _panel, onChanged: (index) => setState(() => _panel = index),
        labels: const ['Members', 'Workspace settings'], icons: const [Icons.people_outline, Icons.settings_outlined],
        sections: [
          current == null ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Choose a team in Workspace settings to view its members.')))
            : TeamMembersScreen(key: ValueKey(current.id), team: current, api: _api, embedded: true),
          ListView(key: const PageStorageKey('workspace-settings'), padding: const EdgeInsets.all(16), children: [
            const FieldWorkspaceSection(title: 'Workspace boundaries', icon: Icons.folder_shared_outlined,
              child: Text('Each team has a separate local database. Switching teams does not move, delete or upload records from another workspace. Personal records remain separate.')),
            const SizedBox(height: 12),
            ...teams.map((team) => Card(color: team.id == _activeId ? Theme.of(context).colorScheme.secondaryContainer : null,
              child: ListTile(leading: Icon(team.id == _activeId ? Icons.check_circle_outline : Icons.groups_outlined),
                title: Text(team.name), subtitle: Text('${team.role}${team.id == _activeId ? ' / Active workspace' : ''}'),
                trailing: const Icon(Icons.chevron_right), onTap: () => _select(team)))),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Create team')),
            TextButton.icon(onPressed: _personal, icon: const Icon(Icons.person_outline), label: const Text('Switch to Personal workspace')),
          ]),
        ],
        footer: current?.role == 'admin' && _panel == 0 ? FieldWorkspaceSection(
          title: 'Administrator controls', icon: Icons.admin_panel_settings_outlined,
          child: Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () => _invite(current!), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add member')),
            OutlinedButton.icon(onPressed: () => _manageMembers(current!), icon: const Icon(Icons.manage_accounts_outlined), label: const Text('Manage roles')),
          ])) : null,
      );
    }));
}
class TeamMembersScreen extends StatefulWidget {
  final CloudTeam team;
  final CloudApiService api;
  final bool embedded;

  const TeamMembersScreen({super.key, required this.team, required this.api, this.embedded = false});

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  late Future<List<CloudMember>> _members = widget.api.members(widget.team);

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _members = widget.api.members(widget.team);
    });
  }

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
        appBar: widget.embedded ? null : AppBar(title: Text('${widget.team.name} members')),
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
                  trailing: widget.team.role != 'admin' ? Text(member.role) : isCurrentUser
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
