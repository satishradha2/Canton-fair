import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/update_service.dart';
import 'data/app_lock_service.dart';
import 'data/language_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/captures_screen.dart';
import 'screens/shortlist_screen.dart';
import 'screens/followup_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/export_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_screen.dart';

class CantonFairApp extends StatefulWidget {
  const CantonFairApp({super.key});

  @override
  State<CantonFairApp> createState() => _CantonFairAppState();
}

class _CantonFairAppState extends State<CantonFairApp>
    with WidgetsBindingObserver {
  int _index = 0;
  final _updates = UpdateService();
  bool _checkedStartupUpdate = false;
  final _appLock = AppLockService();
  final _languageService = LanguageService();
  bool _lockReady = false;
  bool _locked = false;
  String _language = 'en';

  late final _screens = [
    DashboardScreen(),
    CapturesScreen(),
    ShortlistScreen(),
    FollowUpScreen(),
    AnalyticsScreen(),
    ExportScreen(),
    SettingsScreen(
      onAppLockChanged: _refreshAppLock,
      onLanguageChanged: _changeLanguage,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAppLock();
    _loadLanguage();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkForStartupUpdate());
  }

  Future<void> _loadLanguage() async {
    final language = await _languageService.load();
    if (mounted) setState(() => _language = language);
  }

  Future<void> _changeLanguage(String language) async {
    await _languageService.save(language);
    if (mounted) setState(() => _language = language);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _lockReady) {
      _refreshAppLock(lockWhenEnabled: true);
    }
  }

  Future<void> _refreshAppLock({bool lockWhenEnabled = false}) async {
    final enabled = await _appLock.isEnabled;
    if (!mounted) return;
    final shouldLock = enabled && (lockWhenEnabled || _locked || !_lockReady);
    setState(() {
      _lockReady = true;
      _locked = shouldLock;
    });
  }

  Future<void> _checkForStartupUpdate() async {
    if (_checkedStartupUpdate) return;
    _checkedStartupUpdate = true;

    try {
      final update = await _updates.checkLatest();
      if (!mounted || !update.updateAvailable) return;

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'A newer Canton Fair CRM APK is ready.\n\n'
            'Installed: ${update.currentVersion}\n'
            'Latest: ${update.latestVersion}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download'),
              onPressed: () {
                Navigator.pop(ctx);
                _openUpdateUrl(update.apkUrl ?? update.releaseUrl);
              },
            ),
          ],
        ),
      );
    } catch (_) {
      // Update checks should never block the offline-first field workflow.
    }
  }

  Future<void> _openUpdateUrl(String url) async {
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
    if (!_lockReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_locked) {
      return AppLockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return AppLanguage(
        code: _language,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.apartment,
                        color: AppColors.primary, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text([
                    tr(context, 'dashboard'),
                    tr(context, 'captures'),
                    tr(context, 'shortlist'),
                    tr(context, 'followUps'),
                    tr(context, 'analytics'),
                    tr(context, 'export'),
                    tr(context, 'settings'),
                  ][_index])),
                ],
              ),
            ),
            body: _screens[_index],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.dashboard),
                    label: tr(context, 'dashboard')),
                NavigationDestination(
                    icon: const Icon(Icons.record_voice_over),
                    label: tr(context, 'capture')),
                NavigationDestination(
                    icon: const Icon(Icons.star),
                    label: tr(context, 'shortlist')),
                NavigationDestination(
                    icon: const Icon(Icons.event),
                    label: tr(context, 'followUps')),
                NavigationDestination(
                    icon: const Icon(Icons.insights),
                    label: tr(context, 'analytics')),
                NavigationDestination(
                    icon: const Icon(Icons.file_upload),
                    label: tr(context, 'export')),
                NavigationDestination(
                    icon: const Icon(Icons.settings),
                    label: tr(context, 'settings')),
              ],
            ),
          ),
        ));
  }
}
