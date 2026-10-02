import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/cloud_sync_service.dart';
import 'data/appearance_service.dart';
import 'widgets/enterprise_dashboard.dart';
import 'widgets/app_update_gate.dart';
import 'data/team_workspace_service.dart';
import 'data/fair_capture_service.dart';
import 'models/models.dart';
import 'screens/master_data_screen.dart';
import 'screens/minimal_ocr_contact_screen.dart';
import 'screens/supplier_contacts_screen.dart';
import 'screens/team_setup_screen.dart';
import 'screens/shortlists_screen.dart';
import 'screens/company_visits_screen.dart';
import 'screens/security_settings_screen.dart';

class CantonFairApp extends StatelessWidget {
  const CantonFairApp({super.key});

  @override
  Widget build(BuildContext context) => const AppUpdateGate(child: _FairExpertHome());
}
class _FairExpertHome extends StatefulWidget {
  const _FairExpertHome();
  @override
  State<_FairExpertHome> createState() => _FairExpertHomeState();
}

class _FairExpertHomeState extends State<_FairExpertHome> {
  final _workspaceService = TeamWorkspaceService();
  TeamWorkspace? _workspace;
  bool _syncing = false;
  List<Trip> _fairs = [];
  Trip? _selectedFair;
  String? _fairError;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
    _loadFairs();
  }

  Future<void> _loadFairs({bool reset = false}) async {
    try {
      final fairs = await FairCaptureService.fairs();
      if (!mounted) return;
      setState(() {
        final selectedId = reset ? null : _selectedFair?.id;
        _fairs = fairs;
        _selectedFair = null;
        for (final fair in fairs) {
          if (fair.id == selectedId) _selectedFair = fair;
        }
        _fairError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _fairError = 'Could not load fairs: $error');
    }
  }

  Future<void> _openMasters() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MasterDataScreen()));
    await _loadFairs();
  }

  Future<void> _loadWorkspace() async {
    final workspace = await _workspaceService.load();
    if (mounted) setState(() => _workspace = workspace);
  }

  Future<void> _openWorkspaceSetup() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSetupScreen()));
    await _loadWorkspace();
    await _loadFairs(reset: true);
  }

  Future<void> _syncNow() async {
    if (_workspace == null) return _openWorkspaceSetup();
    setState(() => _syncing = true);
    try {
      await CloudSyncService().syncTeamWorkspace();
      await _loadFairs();
      if (mounted) _message('Sync completed successfully.');
    } catch (error) {
      if (mounted) _message('Sync could not complete: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fair Expert'),
        actions: [
          IconButton(tooltip: 'Check for updates',
            onPressed: () => AppUpdateGate.check(context),
            icon: const Icon(Icons.system_update_outlined)),
          IconButton(
            tooltip: 'Switch light / dark theme',
            onPressed: () => AppearanceService().save(
              theme.brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark),
            icon: Icon(theme.brightness == Brightness.dark
                ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
          IconButton(tooltip: 'Security & biometric sign-in',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SecuritySettingsScreen())),
            icon: const Icon(Icons.fingerprint)),
          IconButton(tooltip: 'Sign out',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [colors.secondaryContainer.withValues(alpha: 0.55),
              theme.scaffoldBackgroundColor, colors.primaryContainer.withValues(alpha: 0.45)])),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth > 960 ? 960.0 : constraints.maxWidth;
            final columns = width >= 650 ? 3 : 2;
            final gap = width < 360 ? 10.0 : 12.0;
            final padding = width < 360 ? 12.0 : 20.0;
            final tileWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EnterpriseGlassPanel(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.location_on_outlined, color: colors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('YOUR FAIR WORKSPACE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.5, fontWeight: FontWeight.w800))),
                      IconButton(tooltip: 'Create fair, hall or category',
                        onPressed: _openMasters,
                        icon: const Icon(Icons.add_circle_outline)),
                    ]),
                    if (_fairError != null)
                      Padding(padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_fairError!, style: TextStyle(color: colors.error))),
                    DropdownButtonFormField<int>(
                      key: ValueKey(_selectedFair?.id),
                      initialValue: _selectedFair?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select fair to start scanning',
                        prefixIcon: Icon(Icons.event_outlined)),
                      items: _fairs.map((fair) => DropdownMenuItem(
                        value: fair.id!, child: Text(fair.name))).toList(),
                      onChanged: (id) {
                        if (id != null) {
                          setState(() => _selectedFair =
                            _fairs.firstWhere((fair) => fair.id == id));
                        }
                      },
                    ),
                    if (_fairs.isEmpty)
                      Padding(padding: const EdgeInsets.only(top: 8),
                        child: Text('Use + to create a fair, or Sync to receive team fairs.',
                          style: theme.textTheme.bodySmall)),
                  ])),
                  const SizedBox(height: 18),
                  Text('Your field desk', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Capture. Connect. Follow through.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Wrap(spacing: gap, runSpacing: gap, children: [
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.document_scanner_outlined,
                      title: 'Scan card',
                      subtitle: _selectedFair == null ? 'Select a fair first' : 'Front + back, AI review',
                      highlight: true,
                      onTap: _selectedFair == null ? null : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => MinimalOcrContactScreen(fair: _selectedFair!))))),
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.business_outlined, title: 'Companies',
                      subtitle: 'Contacts & products',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SupplierContactsScreen(fairId: _selectedFair?.id))))),
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.event_available_outlined, title: 'Visits',
                      subtitle: 'Factory & office',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CompanyVisitsScreen())))),
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.bookmarks_outlined, title: 'Shortlists',
                      subtitle: 'Suppliers & products',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ShortlistsScreen())))),
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.dataset_outlined, title: 'Masters',
                      subtitle: 'Fairs, halls, categories', onTap: _openMasters)),
                    SizedBox(width: tileWidth, child: EnterpriseActionTile(
                      icon: Icons.sync_rounded, title: 'Sync',
                      subtitle: _syncing ? 'Syncing your team...' :
                        _workspace == null ? 'Connect workspace' : 'Send & receive updates',
                      busy: _syncing, onTap: _syncNow)),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: colors.secondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      _workspace == null ? 'Review before saving. Connect a workspace to sync.'
                        : 'Team: ${_workspace!.name} | Review before saving.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
                  ]),
                ]),
              )),
            );
          }),
        ),
      ),
    );
  }
}
