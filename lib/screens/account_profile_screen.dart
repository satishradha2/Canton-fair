import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/team_workspace_service.dart';

bool _logoutPending = false;

Future<void> confirmAccountLogout(BuildContext context) async {
  if (_logoutPending || TeamWorkspaceService.busy.value) return;
  _logoutPending = true;
  try {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Log out of this device?'),
      content: const Text('Offline records and photos will not be deleted. Sync important changes before logging out. Unsynced records remain on this device and require the same account and workspace to access them again. Other devices stay signed in.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay signed in')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
      ],
    ));
    if (!context.mounted || confirmed != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    // Remove pushed account/workspace pages before AuthGate switches to sign-in.
    navigator.popUntil((route) => route.isFirst);
    try {
      await TeamWorkspaceService.exclusive(() async {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      });
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Could not finish logging out. Check your connection and retry. Offline records were not deleted.'),
        ));
      }
    }
  } finally {
    _logoutPending = false;
  }
}

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});
  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late final Future<TeamWorkspace?> _workspace = TeamWorkspaceService().load();

  Widget _detail(String label, String? value) => ListTile(
    title: Text(label, style: Theme.of(context).textTheme.labelLarge),
    subtitle: SelectableText(value == null || value.trim().isEmpty ? 'Not provided' : value),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
  );

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Scaffold(appBar: AppBar(title: const Text('My profile')),
          body: const Center(child: Text('You are signed out.')));
    }
    final metadata = user.userMetadata ?? <String, dynamic>{};
    final name = (metadata['full_name'] ?? metadata['name'] ?? '').toString().trim();
    final heading = name.isNotEmpty ? name : user.email ?? 'My account';
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(radius: 28, child: Icon(Icons.person_outline, size: 32)),
            const SizedBox(height: 16),
            Text(heading, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Signed-in account'),
          ],
        ))),
        const SizedBox(height: 16),
        Card(child: Column(children: [
          _detail('Full name', name),
          _detail('Email', user.email),
          _detail('Phone', user.phone),
          _detail('Email status', user.emailConfirmedAt == null ? 'Not confirmed' : 'Confirmed'),
          FutureBuilder<TeamWorkspace?>(future: _workspace, builder: (context, snapshot) =>
            _detail('Selected workspace', snapshot.hasError ? 'Could not load workspace'
                : snapshot.connectionState != ConnectionState.done ? 'Loading...'
                : snapshot.data?.name ?? 'Personal workspace')),
        ])),
        ExpansionTile(title: const Text('Account information'), children: [
          _detail('Account ID', user.id),
          _detail('Account created', user.createdAt),
          _detail('Sign-in provider', user.appMetadata['provider']?.toString()),
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: () => confirmAccountLogout(context),
          icon: const Icon(Icons.logout), label: const Text('Log out')),
        const SizedBox(height: 8),
        const Text('Logging out does not delete offline records or photos.', textAlign: TextAlign.center),
      ])),
    );
  }
}
