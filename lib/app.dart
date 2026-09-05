import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/update_service.dart';
import 'data/app_lock_service.dart';
import 'data/language_service.dart';
import 'data/sync_status_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/captures_screen.dart';
import 'screens/shortlist_screen.dart';
import 'screens/followup_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/export_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/activity_feed_screen.dart';
import 'screens/sourcing_briefs_screen.dart';
import 'screens/procurement_workspace_screen.dart';
import 'widgets/app_lock_screen.dart';
import 'widgets/enterprise_widgets.dart';
import 'theme/app_theme.dart';

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
  final ValueNotifier<CaptureQuickAction?> _captureQuickAction =
      ValueNotifier(null);

  late final _screens = [
    DashboardScreen(
      onCapture: () => _openCapture(CaptureQuickAction.manual),
      onScanQr: () => _openCapture(CaptureQuickAction.qr),
      onScanCard: () => _openCapture(CaptureQuickAction.card),
      onSync: () => setState(() => _index = 6),
      onFollowUps: () => setState(() => _index = 3),
    ),
    CapturesScreen(quickAction: _captureQuickAction),
    ShortlistScreen(),
    FollowUpScreen(),
    AnalyticsScreen(),
    ExportScreen(),
    SettingsScreen(
      onAppLockChanged: _refreshAppLock,
      onLanguageChanged: _changeLanguage,
    ),
    const ActivityFeedScreen(),
    const SourcingBriefsScreen(),
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
    _captureQuickAction.dispose();
    super.dispose();
  }

  void _openCapture(CaptureQuickAction action) {
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureQuickAction.value = action;
    });
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

  static const _destinations = [0, 1, 2, 3, 9];
  static const _labels = ['Today', 'Suppliers', 'Shortlist', 'Tasks', 'Workspace'];
  static const _icons = [
    Icons.dashboard_outlined, Icons.storefront_outlined, Icons.star_border_rounded,
    Icons.checklist_rounded, Icons.grid_view_rounded,
  ];
  static const _selectedIcons = [
    Icons.dashboard_rounded, Icons.storefront_rounded, Icons.star_rounded,
    Icons.checklist_rounded, Icons.grid_view_rounded,
  ];

  int get _navigationIndex => _index <= 3 ? _index : 4;
  void _selectDestination(int index) => setState(() => _index = _destinations[index]);

  Widget _workspaceHub() => EnterprisePage(
    title: 'Workspace',
    subtitle: 'Your sourcing tools, team records, and workspace controls. Choose a task to continue.',
    children: [
      _toolGroup('SOURCE & FOLLOW UP', [
        ('Suppliers', 'Contacts, products, files and booth visits', Icons.storefront_outlined, () => setState(() => _index = 1)),
        ('Sourcing briefs', 'Define requirements for your next purchase', Icons.assignment_outlined, () => setState(() => _index = 8)),
        ('Tasks & follow-ups', 'Meetings, reminders and next actions', Icons.checklist_rounded, () => setState(() => _index = 3)),
        ('Procurement', 'Review quotes, costs and purchase decisions', Icons.account_tree_outlined,
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProcurementWorkspaceScreen()))),
      ]),
      const SizedBox(height: 28),
      _toolGroup('REPORT & MANAGE', [
        ('Analytics', 'Track sourcing progress and trip performance', Icons.insights_outlined, () => setState(() => _index = 4)),
        ('Export reports', 'Share records as CSV or PDF', Icons.ios_share_outlined, () => setState(() => _index = 5)),
        ('Team activity', 'See the workspace change history', Icons.history_rounded, () => setState(() => _index = 7)),
        ('Settings & sync', 'Team selection, backups, security and updates', Icons.settings_outlined, () => setState(() => _index = 6)),
      ]),
    ],
  );

  Widget _toolGroup(String title, List<(String, String, IconData, VoidCallback)> tools) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.muted,
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: tools.map((tool) =>
            SizedBox(width: width, child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: tool.$4, child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFECF2F2), borderRadius: BorderRadius.circular(12)),
                    child: Icon(tool.$3, size: 22, color: AppColors.primary)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tool.$1, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 5),
                    Text(tool.$2, style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.muted),
                ]),
              )),
            )),
          ).toList());
        }),
      ]);

  Widget _syncStrip() => ValueListenableBuilder<int>(
    valueListenable: SyncStatusService.changes,
    builder: (context, _, __) => FutureBuilder<SyncStatus>(
      future: SyncStatusService().load(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? const SyncStatus();
        final syncing = SyncStatusService.isSyncing.value;
        final attention = snapshot.hasError || status.lastError != null || status.conflicts > 0;
        final color = attention ? AppColors.danger : AppColors.teal;
        final label = syncing ? 'Sync in progress'
            : attention ? 'Sync needs attention'
            : status.lastSyncedAt == null ? 'Saved on this device' : 'Last sync completed';
        return Material(color: Colors.white, child: InkWell(
          onTap: () => setState(() => _index = 6),
          child: Semantics(button: true, label: '$label. Open sync settings.',
            excludeSemantics: true, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(children: [
                Icon(syncing ? Icons.sync : attention ? Icons.error_outline : Icons.check_circle_outline,
                    size: 15, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
                const Text('Sync settings', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
              ]),
            )),
        ));
      },
    ),
  );

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
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return Scaffold(
          body: Row(children: [
            if (wide) ...[
              SafeArea(child: NavigationRail(
                selectedIndex: _navigationIndex,
                onDestinationSelected: _selectDestination,
                extended: constraints.maxWidth >= 1180,
                minWidth: 88,
                minExtendedWidth: 216,
                labelType: constraints.maxWidth >= 1180
                    ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: constraints.maxWidth >= 1180
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.business_center_outlined, color: AppColors.teal),
                          SizedBox(width: 12),
                          Text('CANTON FAIR', style: TextStyle(
                              fontSize: 12, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
                        ])
                      : const Icon(Icons.business_center_outlined, color: AppColors.teal),
                ),
                destinations: List.generate(_labels.length, (index) => NavigationRailDestination(
                  icon: Icon(_icons[index]), selectedIcon: Icon(_selectedIcons[index]),
                  label: Text(_labels[index]),
                )),
              )),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: Column(children: [
              Expanded(child: SafeArea(
                bottom: false,
                child: Align(alignment: Alignment.topCenter,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1320),
                    child: _index == 9 ? _workspaceHub() : _screens[_index])),
              )),
              const Divider(),
              SafeArea(top: false, bottom: wide, child: _syncStrip()),
            ])),
          ]),
          bottomNavigationBar: wide ? null : NavigationBar(
            selectedIndex: _navigationIndex,
            onDestinationSelected: _selectDestination,
            destinations: List.generate(_labels.length, (index) => NavigationDestination(
              icon: Icon(_icons[index]), selectedIcon: Icon(_selectedIcons[index]),
              label: _labels[index],
            )),
          ),
        );
      }),
    );
  }
}
