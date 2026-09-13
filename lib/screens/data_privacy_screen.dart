import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/database.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../widgets/enterprise_widgets.dart';

class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  final _db = TradeDatabase.instance;
  final _backup = BackupService();
  late Future<List<Trip>> _trips = _db.getTrips();
  bool _busy = false;

  void _refresh() => setState(() => _trips = _db.getTrips());

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Export and delete')),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteTrip(Trip trip) async {
    if (!await _confirm('Delete ${trip.name}?',
        'A complete recovery backup will be created first. The trip, suppliers, products, contacts, meetings and files will then be deleted.')) {
      return;
    }
    setState(() => _busy = true);
    try {
      final backup = await _backup.createBackup();
      await _db.deleteTripCascade(trip.id!);
      await _db.logAudit(
          'Trip deleted', '${trip.name}; recovery backup: ${backup.path}');
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Trip deleted. Recovery backup retained.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (await TeamWorkspaceService().load() != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Switch to Personal workspace before deleting all data.')));
      }
      return;
    }
    if (!await _confirm('Delete all personal data?',
        'A complete recovery backup will be created first. All personal workspace records and local attachment files will be removed.')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _backup.createBackup();
      final count = await _db.deleteAllPersonalData();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('$count records deleted. Recovery backup retained.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Data and privacy')),
        body: FutureBuilder<List<Trip>>(
          future: _trips,
          builder: (context, snapshot) => EnterprisePage(
            title: 'Privacy controls',
            subtitle:
                'Every destructive action creates a local recovery backup before removing records.',
            children: [
              SectionPanel(
                title: 'Delete by trip',
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.data?.isEmpty ?? true
                        ? const EmptyState(
                            icon: Icons.event_busy_outlined,
                            title: 'No trips to delete',
                            message:
                                'Your current workspace has no trip records.')
                        : Column(
                            children: [
                              for (final trip in snapshot.data!)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(trip.name),
                                  subtitle: Text(trip.city),
                                  trailing: IconButton(
                                    tooltip: 'Delete trip',
                                    onPressed:
                                        _busy ? null : () => _deleteTrip(trip),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                            ],
                          ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Delete everything',
                subtitle: 'Available only in the Personal workspace.',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : _deleteAll,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Export backup and delete all'),
                ),
              ),
            ],
          ),
        ),
      );
}
