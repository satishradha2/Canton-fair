import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updates = UpdateService();
  bool _checking = false;

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    try {
      final update = await _updates.checkLatest();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(update.updateAvailable ? 'Update available' : 'App is up to date'),
          content: Text(
            'Current: ${update.currentVersion}\nLatest: ${update.latestVersion}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            if (update.apkUrl != null || update.updateAvailable)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openUrl(update.apkUrl ?? update.releaseUrl);
                },
                child: const Text('Download'),
              ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update check failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('App updates'),
            subtitle: const Text('Check GitHub Releases for the latest APK'),
            trailing: _checking
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkForUpdate,
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock),
            title: Text('App lock'),
            subtitle: Text('Planned: PIN / biometrics security for supplier data'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_upload),
            title: Text('Backup'),
            subtitle: Text('Planned: cloud sync profile + restore by trip'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.delete_forever),
            title: Text('Delete data'),
            subtitle: Text('Planned: per-trip wipe, export-before-delete workflow'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.language),
            title: Text('Language'),
            subtitle: Text('Planned: English, Chinese, Hindi'),
          ),
        ),
      ],
    );
  }
}

