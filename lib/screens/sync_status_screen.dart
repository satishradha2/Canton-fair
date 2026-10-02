import 'package:flutter/material.dart';
import '../data/cloud_sync_service.dart';
import '../data/sync_status_service.dart';
import '../data/team_workspace_service.dart';
import '../widgets/field_workspace.dart';
import 'team_setup_screen.dart';
import 'phone_cleanup_screen.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});
  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}
class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final _sync = CloudSyncService();
  final _status = SyncStatusService();
  late Future<SyncStatus> _current;
  late Future<List<CloudConflict>> _conflicts;
  late Future<({int records, int files, int blocked, int deletions})> _pending;
  late Future<TeamWorkspace?> _team;
  bool _syncing = false;
  @override
  void initState() { super.initState(); _load(); SyncStatusService.isSyncing.addListener(_syncChanged); }
  @override
  void dispose() { SyncStatusService.isSyncing.removeListener(_syncChanged); super.dispose(); }
  void _load() {
    _current = _status.load(); _conflicts = _sync.conflicts();
    _pending = _sync.pendingUploads(); _team = TeamWorkspaceService().load();
  }
  void _refresh() { if (mounted) setState(_load); }
  void _syncChanged() {
    if (!mounted) return;
    setState(() {});
    if (!SyncStatusService.isSyncing.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _refresh(); });
    }
  }
  bool get _running => _syncing || SyncStatusService.isSyncing.value;
  Future<void> _resolve(CloudConflict conflict, bool local) async {
    try {
      if (local) { await _sync.keepLocalConflict(conflict); }
      else { await _sync.useCloudConflict(conflict); }
      _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resolve this conflict: $error')));
    }
  }
  Future<void> _syncNow() async {
    if (_running || TeamWorkspaceService.isOperationInProgress) return;
    setState(() => _syncing = true);
    try { await _sync.syncTeamWorkspace(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $error'))); }
    finally { if (mounted) { setState(() => _syncing = false); _refresh(); } }
  }
  Widget _metric(String title, String value, IconData icon, {String? detail}) => Card(
    child: ListTile(leading: Icon(icon, color: Theme.of(context).colorScheme.secondary),
      title: Text(title), subtitle: detail == null ? null : Text(detail),
      trailing: Text(value, style: Theme.of(context).textTheme.titleLarge)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sync center'), actions: [
      IconButton(tooltip: 'Refresh status', onPressed: _running ? null : _refresh, icon: const Icon(Icons.refresh)),
    ]),
    body: FutureBuilder<TeamWorkspace?>(future: _team, builder: (context, teamSnapshot) {
      final team = teamSnapshot.data;
      return Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          FieldWorkspaceHeader(eyebrow: 'DEVICE & CLOUD', title: team?.name ?? 'Personal workspace',
            subtitle: 'Saved records and attachments are shared through your selected team. Unsaved drafts stay on this phone.', icon: Icons.cloud_sync_outlined),
          const SizedBox(height: 16), if (_running) const LinearProgressIndicator(),
          if (team != null) Card(child: ListTile(
            leading: const Icon(Icons.phonelink_erase_outlined),
            title: const Text('Phone storage & cleanup approvals'),
            subtitle: const Text('Clear phone copies only. Cloud records and login accounts are kept.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _running ? null : () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneCleanupScreen()));
              _refresh();
            })),
          if (teamSnapshot.hasError) Text('Could not read workspace: ${teamSnapshot.error}'),
          if (teamSnapshot.connectionState == ConnectionState.done && team == null)
            Card(child: ListTile(title: const Text('Connect a team to sync'), subtitle: const Text('Personal records are not automatically uploaded to a team.'),
              trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSetupScreen())))),
          FutureBuilder<SyncStatus>(future: _current, builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Could not read sync status: ${snapshot.error}');
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            final status = snapshot.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FieldWorkspaceSection(title: 'Last successful sync', icon: Icons.schedule, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status.lastSyncedAt?.toLocal().toString().split('.').first ?? 'No successful sync yet'),
                const SizedBox(height: 8), Text('${status.uploaded} uploaded / ${status.downloaded} downloaded in the last successful sync.'),
              ])),
              if (status.lastError != null) FieldWorkspaceSection(title: 'Last sync failure', icon: Icons.error_outline,
                subtitle: 'Saved local records are retained. Resolve the problem and retry.',
                child: SelectableText(status.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]);
          }),
          FutureBuilder<({int records, int files, int blocked, int deletions})>(future: _pending, builder: (context, snapshot) {
            if (snapshot.hasError) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Queue could not be checked: ${snapshot.error}. Wait for the current operation, then refresh.')));
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            final queue = snapshot.data!;
            return Column(children: [
              _metric('Pending uploads', '${queue.records}', Icons.upload_outlined, detail: 'New or changed saved records, including attachments.'),
              _metric('Pending files', '${queue.files}', Icons.attach_file, detail: 'Included in the pending upload count.'),
              _metric('Pending deletions', '${queue.deletions}', Icons.delete_outline),
              if (queue.blocked > 0) _metric('Records needing attention', '${queue.blocked}', Icons.warning_amber_outlined, detail: 'Missing files or unresolved parent links can prevent upload.'),
            ]);
          }),
          FutureBuilder<List<CloudConflict>>(future: _conflicts, builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Could not read conflicts: ${snapshot.error}');
            if (!snapshot.hasData) return const SizedBox.shrink();
            final conflicts = snapshot.data!;
            return FieldWorkspaceSection(title: 'Conflicts (${conflicts.length})', icon: Icons.compare_arrows,
              child: conflicts.isEmpty ? const Text('No unresolved conflicts on this phone.') : Column(children: [
                for (final conflict in conflicts) ListTile(contentPadding: EdgeInsets.zero,
                  title: Text('${conflict.recordType} / ${conflict.recordId}'),
                  subtitle: const Text('Changed on another device. Choose which saved version to keep.'),
                  trailing: PopupMenuButton<String>(enabled: !_running, onSelected: (value) => _resolve(conflict, value == 'local'), itemBuilder: (_) => const [
                    PopupMenuItem(value: 'local', child: Text('Keep this device')), PopupMenuItem(value: 'cloud', child: Text('Use cloud version')),
                  ])),
              ]));
          }),
        ])),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity,
          child: FilledButton.icon(onPressed: _running || team == null ? null : _syncNow,
            icon: _running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            label: Text(_running ? 'Syncing...' : 'Sync now / retry'))))),
      ]);
    }));
}
