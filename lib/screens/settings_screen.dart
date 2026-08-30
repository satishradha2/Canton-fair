import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_service.dart';
import '../data/backup_service.dart';
import '../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updates = UpdateService();
  final _backup = BackupService();
  final _database = TradeDatabase.instance;
  bool _checking = false;
  bool _creatingBackup = false;

  Future<void> _createBackup() async {
    setState(() => _creatingBackup = true);
    try {
      await _backup.createAndShareBackup();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _creatingBackup = false);
    }
  }

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

  Future<void> _showAuditHistory() async {
    final records = await _database.getAuditLogs();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit history',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text('Recent actions performed on this device.',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                Expanded(
                  child: records.isEmpty
                      ? const Center(child: Text('No recorded activity yet.'))
                      : ListView.separated(
                          itemCount: records.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final record = records[index];
                            final timestamp = DateTime.tryParse(
                                record['created_at'] as String? ?? '');
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.history),
                              title: Text(
                                  record['action'] as String? ?? 'Activity'),
                              subtitle:
                                  Text(record['details'] as String? ?? ''),
                              trailing: Text(
                                timestamp == null
                                    ? ''
                                    : '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}\n${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                  subtitle: 'Coming next: PIN and biometric security'),
              _settingTile(
                  icon: Icons.cloud_upload,
                  title: 'Export backup',
                  subtitle:
                      'Create a shareable local JSON backup of your records',
                  trailing: _creatingBackup
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _creatingBackup ? null : _createBackup),
              _settingTile(
                icon: Icons.history,
                title: 'Audit history',
                subtitle: 'Review recent backup and data-management activity',
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAuditHistory,
              ),
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
