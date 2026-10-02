import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/cloud_sync_service.dart';
import 'data/team_workspace_service.dart';
import 'data/fair_capture_service.dart';
import 'models/models.dart';
import 'screens/master_data_screen.dart';
import 'screens/minimal_ocr_contact_screen.dart';
import 'screens/supplier_contacts_screen.dart';
import 'screens/team_setup_screen.dart';
import 'screens/shortlists_screen.dart';
import 'screens/company_visits_screen.dart';

class CantonFairApp extends StatelessWidget {
  const CantonFairApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Fair Expert',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E69)),
          scaffoldBackgroundColor: const Color(0xFFF4F7F6),
        ),
        home: const _FairExpertHome(),
      );
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Fair Expert'),
          actions: [IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout_rounded))],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Choose your fair', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (_fairError != null) Text(_fairError!),
                    DropdownButtonFormField<int>(
                      key: ValueKey(_selectedFair?.id),
                      initialValue: _selectedFair?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Fair', border: OutlineInputBorder()),
                      items: _fairs.map((fair) => DropdownMenuItem(value: fair.id!, child: Text(fair.name))).toList(),
                      onChanged: (id) { if (id != null) setState(() => _selectedFair = _fairs.firstWhere((fair) => fair.id == id)); },
                    ),
                    if (_fairs.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Create a fair in Masters or sync your team fairs to get started.')),
                    TextButton(onPressed: _openMasters, child: const Text('Open Masters')),
                  ]))),
                  const SizedBox(height: 20),
                  Text('Capture contacts.\nKeep your team in sync.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF102B3A))),
                  const SizedBox(height: 10),
                  const Text('Capture contacts and products, shortlist promising suppliers, and keep your team in sync.', style: TextStyle(color: Color(0xFF536B76), height: 1.45)),
                  const SizedBox(height: 28),
                  _ActionCard(
                    icon: Icons.document_scanner_outlined,
                    title: 'Scan business card',
                    description: _selectedFair == null ? 'Choose your fair above before scanning a business card.' : 'Scan and save contacts for ${_selectedFair!.name}.',
                    actionLabel: 'Start scan',
                    onTap: _selectedFair == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MinimalOcrContactScreen(fair: _selectedFair!))),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.business_outlined,
                    title: 'Companies and contacts',
                    description: 'Open one supplier record to see every person saved from its business cards.',
                    actionLabel: 'View companies',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierContactsScreen(fairId: _selectedFair?.id))),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.event_available_outlined,
                    title: 'Upcoming visits',
                    description: 'Plan factory and office appointments, continue visit workpads, and review completed visits.',
                    actionLabel: 'Visits & appointments',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanyVisitsScreen())),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.bookmarks_outlined,
                    title: 'Shortlists',
                    description: 'Review supplier and product interests separately. Shortlisting is not purchasing approval.',
                    actionLabel: 'Open shortlists',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShortlistsScreen())),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.dataset_outlined,
                    title: 'Masters',
                    description: 'Create the shared fair, hall, and product-category lists used by your team.',
                    actionLabel: 'Manage masters',
                    onTap: _openMasters,
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.sync_rounded,
                    title: 'Sync',
                    description: _workspace == null ? 'Connect a team workspace to synchronize saved contacts.' : 'Connected to ${_workspace!.name}. Upload and receive your latest contacts.',
                    actionLabel: _workspace == null ? 'Connect workspace' : 'Sync now',
                    busy: _syncing,
                    onTap: _syncNow,
                  ),
                  const SizedBox(height: 24),
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xFFE2F0EE), borderRadius: BorderRadius.all(Radius.circular(16))),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.verified_user_outlined), SizedBox(width: 12), Expanded(child: Text('Every card is reviewed before it is saved. Sync only after the contact is ready for your team.'))]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.description, required this.actionLabel, required this.onTap, this.busy = false});
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD6E1E0))),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 24, child: Icon(icon, size: 26)),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: Color(0xFF536B76), height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : onTap, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(actionLabel))),
          ]),
        ),
      );
}
