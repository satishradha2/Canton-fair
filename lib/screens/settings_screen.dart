import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_service.dart';
import '../widgets/enterprise_widgets.dart';

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
          title: Text(update.updateAvailable
              ? 'Update available'
              : 'App is up to date'),
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
    return EnterprisePage(
      title: 'Settings',
      subtitle:
          'Device-level controls, app updates, backup readiness, and data governance.',
      children: [
        SectionPanel(
          title: 'System',
          child: Column(
            children: [
              _settingTile(
                icon: Icons.system_update,
                title: 'App updates',
                subtitle: 'Check GitHub Releases for the latest APK',
                trailing: _checking
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _checking ? null : _checkForUpdate,
              ),
              _settingTile(
                  icon: Icons.lock,
                  title: 'App lock',
                  subtitle: 'Planned: PIN and biometric security'),
              _settingTile(
                  icon: Icons.cloud_upload,
                  title: 'Backup',
                  subtitle: 'Planned: cloud sync profile and trip restore'),
              _settingTile(
                  icon: Icons.delete_forever,
                  title: 'Delete data',
                  subtitle: 'Planned: export-before-delete workflow'),
              _settingTile(
                  icon: Icons.language,
                  title: 'Language',
                  subtitle: 'Planned: English, Chinese, Hindi'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
