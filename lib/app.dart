import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/update_service.dart';
import 'data/language_service.dart';
import 'data/sync_status_service.dart';
import 'data/database.dart';
import 'data/auto_sync_service.dart';
import 'models/models.dart';
import 'screens/captures_screen.dart';
import 'screens/account_profile_screen.dart';
import 'screens/field_operations_screen.dart';
import 'screens/field_visit_assistant_screen.dart';
import 'screens/supplier_detail_screen.dart';
import 'screens/sync_status_screen.dart';
import 'screens/team_setup_screen.dart';
import 'widgets/enterprise_widgets.dart';
import 'theme/app_theme.dart';

class CantonFairApp extends StatefulWidget {
  const CantonFairApp({super.key});

  @override
  State<CantonFairApp> createState() => _CantonFairAppState();
}

class _CantonFairAppState extends State<CantonFairApp>
    with WidgetsBindingObserver {
  static const _quickActions = MethodChannel('canton_fair_crm/quick_action');
  int _index = 0;
  final _updates = UpdateService();
  bool _checkedStartupUpdate = false;
  final _languageService = LanguageService();
  String _language = 'en';
  final ValueNotifier<CaptureQuickAction?> _captureQuickAction =
      ValueNotifier(null);

  late final _screens = [
    CapturesScreen(quickAction: _captureQuickAction),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLanguage();
    AutoSyncService.instance.start();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkForStartupUpdate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeQuickAction());
  }

  Future<void> _takeQuickAction() async {
    try {
      final value = await _quickActions.invokeMethod<String>('take');
      if (!mounted || value == null) return;
      if (value.endsWith('/card')) {
        _openCapture(CaptureQuickAction.card);
      } else if (value.endsWith('/qr')) {
        _openCapture(CaptureQuickAction.qr);
      } else if (value.endsWith('/supplier')) {
        _openCapture(CaptureQuickAction.manual);
      }
    } on PlatformException {
      // Launcher shortcuts are Android-only; normal navigation remains available.
    }
  }

  Future<void> _loadLanguage() async {
    final language = await _languageService.load();
    if (mounted) setState(() => _language = language);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureQuickAction.dispose();
    AutoSyncService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _takeQuickAction();
  }

  void _openCapture(CaptureQuickAction action) {
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureQuickAction.value = action;
    });
  }

  Future<void> _openCaptureMenu() async {
    final action = await showModalBottomSheet<CaptureQuickAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: Text(tr(context, 'quickCapture')),
              subtitle: const Text('Supplier, booth, contact, and category'),
              onTap: () => Navigator.pop(context, CaptureQuickAction.quick),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_turned_in_outlined),
              title: const Text('Guided field visit'),
              subtitle: const Text(
                  'Check in, capture evidence, set next actions, and hand over'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FieldVisitAssistantScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: Text(tr(context, 'fullSupplierCapture')),
              subtitle: const Text(
                  'Products, photos, commercial terms, and next actions'),
              onTap: () => Navigator.pop(context, CaptureQuickAction.manual),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(tr(context, 'scanBusinessCard')),
              subtitle: const Text('Extract supplier and contact details'),
              onTap: () => Navigator.pop(context, CaptureQuickAction.card),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: Text(tr(context, 'scanQr')),
              onTap: () => Navigator.pop(context, CaptureQuickAction.qr),
            ),
          ]),
        ),
      ),
    );
    if (action != null && mounted) _openCapture(action);
  }

  void _openSupplierSearch() {
    showSearch<void>(
      context: context,
      delegate: _SupplierSearchDelegate(),
    );
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
                _downloadAndInstallUpdate(update);
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

  Future<void> _downloadAndInstallUpdate(AppUpdateInfo update) async {
    final progress = ValueNotifier<ApkDownloadProgress?>(null);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading update'),
          content: ValueListenableBuilder<ApkDownloadProgress?>(
            valueListenable: progress,
            builder: (context, value, _) {
              final percentage = value?.fraction == null
                  ? 'Preparing secure download...'
                  : '${(value!.fraction! * 100).clamp(0, 100).round()}% downloaded';
              return Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: value?.fraction),
                const SizedBox(height: 16),
                Text(percentage),
                const SizedBox(height: 8),
                const Text('The installer will open automatically when the file is ready.'),
              ]);
            },
          ),
        ),
      ),
    );
    try {
      await _updates.downloadAndInstall(update, onProgress: (value) => progress.value = value);
    } catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not install the update: $error'),
          action: SnackBarAction(
            label: 'OPEN RELEASE',
            onPressed: () => _openUpdateUrl(update.releaseUrl),
          ),
        ));
      }
    } finally {
      progress.dispose();
    }
  }

  static const _destinations = [0, 1, 2];
  static const _icons = [
    Icons.storefront_outlined,
    Icons.work_outline,
    Icons.person_outline,
  ];
  static const _selectedIcons = [
    Icons.storefront_rounded,
    Icons.work,
    Icons.person,
  ];

  int get _navigationIndex => _index;
  List<String> _labels(BuildContext context) =>
      const ['Field capture', 'Field operations', 'Account'];
  void _selectDestination(int index) =>
      setState(() => _index = _destinations[index]);

  Widget _fieldAccountHub() => EnterprisePage(
        title: 'Account & sync',
        subtitle:
            'Manage your signed-in account and keep field captures shared with your team.',
        children: [
          _toolGroup('MY ACCOUNT', [
            (
              'My profile',
              'Your signed-in account and workspace',
              Icons.person_outline,
              () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AccountProfileScreen()))
            ),
            (
              'Log out',
              'Sign out of this device',
              Icons.logout,
              () => confirmAccountLogout(context)
            ),
          ]),
          const SizedBox(height: 28),
          _toolGroup('TEAM SYNC', [
            (
              'Team workspace',
              'Create a shared workspace, invite members, and manage access',
              Icons.groups_outlined,
              () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TeamSetupScreen()))
            ),
            (
              'Sync status',
              'Review and synchronize your team field captures',
              Icons.sync,
              () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SyncStatusScreen()))
            ),
          ]),
        ],
      );

  Widget _toolGroup(
          String title, List<(String, String, IconData, VoidCallback)> tools) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: tools
                  .map(
                    (tool) => SizedBox(
                        width: width,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              onTap: tool.$4,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(tool.$3,
                                              size: 22,
                                              color: adaptiveAppColor(
                                                  context, AppColors.primary))),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(tool.$1,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall),
                                            const SizedBox(height: 5),
                                            Text(tool.$2,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                          ])),
                                      const SizedBox(width: 8),
                                      Icon(Icons.arrow_forward_ios_rounded,
                                          size: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ]),
                              )),
                        )),
                  )
                  .toList());
        }),
      ]);

  Widget _syncStrip() => ValueListenableBuilder<int>(
        valueListenable: SyncStatusService.changes,
        builder: (context, _, __) => FutureBuilder<SyncStatus>(
          future: SyncStatusService().load(),
          builder: (context, snapshot) {
            final status = snapshot.data ?? const SyncStatus();
            final syncing = SyncStatusService.isSyncing.value;
            final attention = snapshot.hasError ||
                status.lastError != null ||
                status.conflicts > 0;
            final color = attention ? AppColors.danger : AppColors.teal;
            final label = syncing
                ? tr(context, 'syncInProgress')
                : attention
                    ? status.conflicts > 0
                        ? '${status.conflicts} record${status.conflicts == 1 ? '' : 's'} need a sync decision'
                        : status.lastError != null
                            ? 'Sync failed. Tap to review and retry the affected records.'
                            : 'Sync needs setup. Tap to review the required action.'
                    : status.lastSyncedAt == null
                        ? tr(context, 'savedOnDevice')
                        : tr(context, 'lastSyncCompleted');
            return Material(
                color: Theme.of(context).colorScheme.surface,
                child: InkWell(
                  onTap: () => setState(() => _index = 1),
                  child: Semantics(
                      button: true,
                      label: '$label. Open sync settings.',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(children: [
                          Icon(
                              syncing
                                  ? Icons.sync
                                  : attention
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                              size: 15,
                              color: color),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: color,
                                      fontWeight: FontWeight.w600))),
                          Text(tr(context, 'syncSettings'),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ]),
                      )),
                ));
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AppLanguage(
      code: _language,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return Scaffold(
          body: Row(children: [
            if (wide) ...[
              SafeArea(
                  child: NavigationRail(
                selectedIndex: _navigationIndex,
                onDestinationSelected: _selectDestination,
                extended: constraints.maxWidth >= 1180,
                minWidth: 88,
                minExtendedWidth: 216,
                labelType: constraints.maxWidth >= 1180
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: constraints.maxWidth >= 1180
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.business_center_outlined,
                              color: AppColors.teal),
                          SizedBox(width: 12),
                          Text('CANTON FAIR',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                        ])
                      : const Icon(Icons.business_center_outlined,
                          color: AppColors.teal),
                ),
                destinations: List.generate(
                    _labels(context).length,
                    (index) => NavigationRailDestination(
                          icon: Icon(_icons[index]),
                          selectedIcon: Icon(_selectedIcons[index]),
                          label: Text(_labels(context)[index]),
                        )),
              )),
              const VerticalDivider(width: 1),
            ],
            Expanded(
                child: Column(children: [
              Expanded(
                  child: SafeArea(
                bottom: false,
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: _index == 2
                            ? _fieldAccountHub()
                            : _index == 1
                                ? FieldOperationsScreen(
                                    onScanCard: () => _openCapture(
                                        CaptureQuickAction.card),
                                  )
                                : _screens[0])),
              )),
              const Divider(),
              SafeArea(top: false, bottom: wide, child: _syncStrip()),
            ])),
          ]),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _navigationIndex,
                  onDestinationSelected: _selectDestination,
                  destinations: List.generate(
                      _labels(context).length,
                      (index) => NavigationDestination(
                            icon: Icon(_icons[index]),
                            selectedIcon: Icon(_selectedIcons[index]),
                            label: _labels(context)[index],
                          )),
                ),
          floatingActionButton: !wide && _index == 0
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Search suppliers',
                      child: FloatingActionButton.small(
                        heroTag: 'supplierSearch',
                        tooltip: 'Search suppliers',
                        onPressed: _openSupplierSearch,
                        child: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      button: true,
                      label: 'Open capture tools',
                      child: FloatingActionButton.small(
                        heroTag: 'captureMenu',
                        tooltip: 'Capture tools',
                        onPressed: _openCaptureMenu,
                        child: const Icon(Icons.add_a_photo_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'startVisit',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const FieldVisitAssistantScreen()),
                      ),
                      icon: const Icon(Icons.playlist_add_check_circle_outlined),
                      label: const Text('Start visit'),
                    ),
                  ],
                )
              : null,
        );
      }),
    );
  }
}

class _SupplierSearchDelegate extends SearchDelegate<void> {
  _SupplierSearchDelegate()
      : super(
          searchFieldLabel: 'Search supplier, booth, hall, or category',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  final TradeDatabase _db = TradeDatabase.instance;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => query.trim().isEmpty
      ? const Center(
          child: Text('Search suppliers by name, booth, hall, or category.'))
      : _results(context);

  Widget _results(BuildContext context) => FutureBuilder<_WorkspaceSearch>(
        future: _loadWorkspace(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final needle = query.trim().toLowerCase();
          final workspace = snapshot.data!;
          final suppliers = workspace.suppliers.where((supplier) {
            return [
              supplier.name,
              supplier.booth,
              supplier.hall,
              supplier.category,
              supplier.country
            ].any((value) => value.toLowerCase().contains(needle));
          }).toList();
          final products = workspace.products
              .where((entry) => [
                    entry.product.name,
                    entry.product.modelCode,
                    entry.product.specs,
                  ].any((value) => value.toLowerCase().contains(needle)))
              .toList();
          final contacts = workspace.contacts
              .where((entry) => [
                    entry.contact.name,
                    entry.contact.designation,
                    entry.contact.email,
                    entry.contact.phone,
                    entry.contact.whatsapp,
                  ].any((value) => value.toLowerCase().contains(needle)))
              .toList();
          final tasks = workspace.meetings
              .where((entry) => [
                    entry.meeting.outcome,
                    entry.meeting.notes,
                    entry.meeting.assigneeEmail,
                    entry.supplier.name,
                  ].any((value) => value.toLowerCase().contains(needle)))
              .toList();
          final trips = workspace.trips
              .where((trip) => [trip.name, trip.city, trip.notes]
                  .any((value) => value.toLowerCase().contains(needle)))
              .toList();
          if (suppliers.isEmpty &&
              products.isEmpty &&
              contacts.isEmpty &&
              tasks.isEmpty &&
              trips.isEmpty) {
            return const Center(child: Text('No matching supplier found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (suppliers.isNotEmpty) ...[
                const _SearchGroupLabel('SUPPLIERS'),
                ...suppliers
                    .map((supplier) => _supplierResult(context, supplier)),
              ],
              if (products.isNotEmpty) ...[
                const _SearchGroupLabel('PRODUCTS'),
                ...products.map((entry) => _supplierResult(
                      context,
                      entry.supplier,
                      icon: Icons.inventory_2_outlined,
                      title: entry.product.name,
                      detail: 'Product at ${entry.supplier.name}',
                    )),
              ],
              if (contacts.isNotEmpty) ...[
                const _SearchGroupLabel('CONTACTS'),
                ...contacts.map((entry) => _supplierResult(
                      context,
                      entry.supplier,
                      icon: Icons.person_outline,
                      title: entry.contact.name,
                      detail:
                          '${entry.contact.designation.isEmpty ? 'Contact' : entry.contact.designation} | ${entry.supplier.name}',
                    )),
              ],
              if (tasks.isNotEmpty) ...[
                const _SearchGroupLabel('FOLLOW-UPS'),
                ...tasks.map((entry) => _supplierResult(
                      context,
                      entry.supplier,
                      icon: entry.meeting.completed
                          ? Icons.task_alt
                          : Icons.event_note_outlined,
                      title: entry.meeting.outcome.isEmpty
                          ? 'Supplier follow-up'
                          : entry.meeting.outcome,
                      detail: entry.supplier.name,
                    )),
              ],
              if (trips.isNotEmpty) ...[
                const _SearchGroupLabel('TRIPS'),
                ...trips.map((trip) => Card(
                        child: ListTile(
                      leading: const Icon(Icons.flight_takeoff_outlined),
                      title: Text(trip.name),
                      subtitle:
                          Text(trip.city.isEmpty ? 'Trip record' : trip.city),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => close(context, null),
                    ))),
              ],
            ],
          );
        },
      );

  Widget _supplierResult(
    BuildContext context,
    Exhibitor supplier, {
    IconData icon = Icons.storefront_outlined,
    String? title,
    String? detail,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
            child: ListTile(
          leading: Icon(icon),
          title: Text(title ?? supplier.name),
          subtitle: Text(detail ??
              [
                if (supplier.booth.isNotEmpty) 'Booth ${supplier.booth}',
                if (supplier.hall.isNotEmpty) supplier.hall,
                if (supplier.category.isNotEmpty) supplier.category,
              ].join(' | ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupplierDetailScreen(supplier: supplier),
          )),
        )),
      );

  Future<_WorkspaceSearch> _loadWorkspace() async {
    final trips = await _db.getTrips();
    final suppliers = await _db.getExhibitors(null);
    final meetings = await _db.getMeetings();
    final supplierById = {for (final item in suppliers) item.id!: item};
    final records = await Future.wait(suppliers.map((supplier) async {
      final contacts = await _db.getContacts(supplier.id!);
      final products = await _db.getProducts(supplier.id!);
      return (supplier: supplier, contacts: contacts, products: products);
    }));
    return _WorkspaceSearch(
      trips: trips,
      suppliers: suppliers,
      contacts: [
        for (final item in records)
          for (final contact in item.contacts)
            _SearchContact(contact, item.supplier),
      ],
      products: [
        for (final item in records)
          for (final product in item.products)
            _SearchProduct(product, item.supplier),
      ],
      meetings: [
        for (final meeting in meetings)
          if (supplierById[meeting.exhibitorId] case final supplier?)
            _SearchMeeting(meeting, supplier),
      ],
    );
  }
}

class _SearchGroupLabel extends StatelessWidget {
  final String label;
  const _SearchGroupLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      );
}

class _WorkspaceSearch {
  final List<Trip> trips;
  final List<Exhibitor> suppliers;
  final List<_SearchContact> contacts;
  final List<_SearchProduct> products;
  final List<_SearchMeeting> meetings;
  const _WorkspaceSearch({
    required this.trips,
    required this.suppliers,
    required this.contacts,
    required this.products,
    required this.meetings,
  });
}

class _SearchContact {
  final Contact contact;
  final Exhibitor supplier;
  const _SearchContact(this.contact, this.supplier);
}

class _SearchProduct {
  final Product product;
  final Exhibitor supplier;
  const _SearchProduct(this.product, this.supplier);
}

class _SearchMeeting {
  final Meeting meeting;
  final Exhibitor supplier;
  const _SearchMeeting(this.meeting, this.supplier);
}
