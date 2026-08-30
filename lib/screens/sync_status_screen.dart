import 'package:flutter/material.dart';

import '../data/cloud_sync_service.dart';
import '../data/sync_status_service.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final _sync = CloudSyncService();
  final _status = SyncStatusService();
  late Future<SyncStatus> _current = _status.load();
  late Future<List<CloudConflict>> _conflicts = _sync.conflicts();
  bool _syncing = false;

  void _refresh() => setState(() {
        _current = _status.load();
        _conflicts = _sync.conflicts();
      });

  Future<void> _keepLocal(CloudConflict conflict) async {
    try {
      await _sync.keepLocalConflict(conflict);
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not keep local version: $error')));
      }
    }
  }

  Future<void> _useCloud(CloudConflict conflict) async {
    try {
      await _sync.useCloudConflict(conflict);
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not use cloud version: $error')));
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final result = await _sync.syncTeamWorkspace();
      await _status.recordSuccess(
        uploaded: result.uploaded,
        downloaded: result.downloaded,
        conflicts: result.conflicts,
      );
    } catch (error) {
      await _status.recordFailure(error);
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sync activity')),
        body: FutureBuilder<SyncStatus>(
          future: _current,
          builder: (context, snapshot) {
            final status = snapshot.data ?? const SyncStatus();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Last successful sync'),
                  subtitle: Text(status.lastSyncedAt?.toLocal().toString() ??
                      'No completed sync yet'),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Last upload'),
                  trailing: Text('${status.uploaded} records'),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Last download'),
                  trailing: Text('${status.downloaded} records'),
                ),
                ListTile(
                  leading: Icon(status.conflicts == 0
                      ? Icons.task_alt
                      : Icons.warning_amber_outlined),
                  title: const Text('Conflicts'),
                  trailing: Text('${status.conflicts}'),
                ),
                FutureBuilder<List<CloudConflict>>(
                  future: _conflicts,
                  builder: (context, conflictSnapshot) {
                    final conflicts = conflictSnapshot.data ?? const [];
                    if (conflicts.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: [
                        const Divider(),
                        ...conflicts.map((conflict) => ListTile(
                              leading: const Icon(Icons.compare_arrows),
                              title: Text('${conflict.recordType} conflict'),
                              subtitle: Text(
                                  'Cloud version ${conflict.remoteVersion} is newer'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) => value == 'local'
                                    ? _keepLocal(conflict)
                                    : _useCloud(conflict),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'local',
                                      child: Text('Keep this device')),
                                  PopupMenuItem(
                                      value: 'cloud',
                                      child: Text('Use cloud version')),
                                ],
                              ),
                            )),
                      ],
                    );
                  },
                ),
                if (status.lastError != null) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('Last sync failed'),
                    subtitle: Text(status.lastError!),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _syncing ? null : _syncNow,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_syncing ? 'Syncing' : 'Retry sync'),
                ),
              ],
            );
          },
        ),
      );
}
