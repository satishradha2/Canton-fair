import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_service.dart';
import '../data/backup_service.dart';
import '../data/database.dart';
import '../data/app_lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function()? onAppLockChanged;

  const SettingsScreen({super.key, this.onAppLockChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updates = UpdateService();
  final _backup = BackupService();
  final _database = TradeDatabase.instance;
  final _appLock = AppLockService();
  bool _checking = false;
  bool _creatingBackup = false;
  bool _restoringBackup = false;
  bool _appLockEnabled = false;

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

  @override
  void initState() {
    super.initState();
    _loadAppLock();
  }

  Future<void> _loadAppLock() async {
    final enabled = await _appLock.isEnabled;
    if (mounted) setState(() => _appLockEnabled = enabled);
  }

  Future<void> _configureAppLock() async {
    if (_appLockEnabled) {
      await _appLock.disable();
      await _loadAppLock();
      await widget.onAppLockChanged?.call();
      return;
    }
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set app lock PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'PIN (4-8 digits)'),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!RegExp(r'^\d{4,8}$').hasMatch(pin.text) ||
                  pin.text != confirm.text) {
                return;
              }
              await _appLock.setPin(pin.text);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    pin.dispose();
    confirm.dispose();
    if (saved == true) {
      await _loadAppLock();
      await widget.onAppLockChanged?.call();
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

  Future<void> _restoreBackup() async {
    setState(() => _restoringBackup = true);
    try {
      final preview = await _backup.selectBackup();
      if (!mounted || preview == null) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace local data?'),
              content: Text(
                'This backup contains ${preview.recordCount} records. Restoring it replaces current trips, suppliers, products, meetings, quotes, attachments, and saved filters on this device. This cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace data'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      final count = await _backup.restoreReplacingLocalData(preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup restored: $count records imported.')),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Backup selection failed: ${error.message ?? error.code}')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup restore failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _restoringBackup = false);
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
                  subtitle: _appLockEnabled
                      ? 'Enabled: PIN and supported biometrics unlock the app'
                      : 'Protect local supplier and pricing data with a PIN',
                  trailing: Switch(
                    value: _appLockEnabled,
                    onChanged: (_) => _configureAppLock(),
                  ),
                  onTap: _configureAppLock),
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
                icon: Icons.settings_backup_restore,
                title: 'Restore backup',
                subtitle:
                    'Replace this device data from a Canton Fair JSON backup',
                trailing: _restoringBackup
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _restoringBackup ? null : _restoreBackup,
              ),
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
