import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_service.dart';
import '../data/backup_service.dart';
import '../data/database.dart';
import '../data/app_lock_service.dart';
import '../data/language_service.dart';
import '../data/team_workspace_service.dart';
import '../data/cloud_sync_service.dart';
import '../data/sync_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import 'team_setup_screen.dart';
import 'sync_status_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function()? onAppLockChanged;
  final Future<void> Function(String language)? onLanguageChanged;

  const SettingsScreen(
      {super.key, this.onAppLockChanged, this.onLanguageChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updates = UpdateService();
  final _backup = BackupService();
  final _database = TradeDatabase.instance;
  final _appLock = AppLockService();
  final _sync = CloudSyncService();
  bool _checking = false;
  bool _creatingBackup = false;
  bool _restoringBackup = false;
  bool _appLockEnabled = false;
  bool _syncing = false;
  String _language = 'en';
  String? _teamName;

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
    _loadLanguage();
    _loadTeamWorkspace();
  }

  Future<void> _loadTeamWorkspace() async {
    final workspace = await TeamWorkspaceService().load();
    if (mounted) setState(() => _teamName = workspace?.name);
  }

  Future<void> _loadLanguage() async {
    final language = await LanguageService().load();
    if (mounted) setState(() => _language = language);
  }

  Future<void> _chooseLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr(context, 'chooseLanguage')),
        children: ['en', 'zh', 'hi']
            .map((code) => RadioListTile<String>(
                  value: code,
                  groupValue: _language,
                  title: Text({
                    'en': tr(context, 'english'),
                    'zh': tr(context, 'chinese'),
                    'hi': tr(context, 'hindi')
                  }[code]!),
                  onChanged: (value) => Navigator.pop(context, value),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    await widget.onLanguageChanged?.call(selected);
    if (!mounted) return;
    setState(() => _language = selected);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, 'languageSaved'))));
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

  Future<void> _syncCloudData() async {
    setState(() => _syncing = true);
    try {
      final result = await _sync.syncTeamWorkspace();
      await SyncStatusService().recordSuccess(
        uploaded: result.uploaded,
        downloaded: result.downloaded,
        conflicts: result.conflicts,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cloud data synced: ${result.uploaded} uploaded, '
              '${result.downloaded} downloaded, ${result.conflicts} conflicts.')));
    } catch (error) {
      await SyncStatusService().recordFailure(error);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cloud sync failed: $error')));
    } finally {
      if (mounted) setState(() => _syncing = false);
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
      title: tr(context, 'settings'),
      subtitle:
          'Device-level controls, app updates, backup readiness, and data governance.',
      children: [
        SectionPanel(
          title: tr(context, 'system'),
          child: Column(
            children: [
              _settingTile(
                icon: Icons.groups,
                title: 'Cloud team',
                subtitle: _teamName == null
                    ? 'Choose the shared team workspace for sync'
                    : 'Workspace: $_teamName',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TeamSetupScreen()));
                  await _loadTeamWorkspace();
                },
              ),
              _settingTile(
                icon: Icons.sync,
                title: 'Sync cloud data',
                subtitle: _teamName == null
                    ? 'Choose a cloud team before syncing'
                    : 'Sync shared records and attachments for $_teamName',
                trailing: _syncing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _syncing || _teamName == null ? null : _syncCloudData,
              ),
              _settingTile(
                icon: Icons.sync_problem_outlined,
                title: 'Sync activity',
                subtitle: 'Review the latest cloud sync, errors, and conflicts',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SyncStatusScreen())),
              ),
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
                icon: Icons.language,
                title: tr(context, 'language'),
                subtitle: {
                  'en': tr(context, 'english'),
                  'zh': tr(context, 'chinese'),
                  'hi': tr(context, 'hindi')
                }[_language]!,
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseLanguage,
              ),
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
