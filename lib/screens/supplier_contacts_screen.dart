import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/supplier_categories_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../widgets/supplier_category_picker.dart';
import '../widgets/company_products_section.dart';
import '../widgets/supplier_shortlist_card.dart';
import '../widgets/field_workspace.dart';
import '../widgets/database_paged_list.dart';
import '../data/record_page_service.dart';
import 'company_visits_screen.dart';

class SupplierContactsScreen extends StatefulWidget {
  const SupplierContactsScreen({super.key, this.companyId, this.fairId});
  final int? companyId;
  final int? fairId;

  @override
  State<SupplierContactsScreen> createState() => _SupplierContactsScreenState();
}

class _SupplierContactsScreenState extends State<SupplierContactsScreen> {
  late Future<_CompanyData?> _company;
  final _directoryKey = GlobalKey<DatabasePagedListState>();
  String? _scope;
  final Set<String> _selectedCategories = {};
  bool _canEdit = false;
  bool _savingCategories = false;
  bool _categoriesChanged = false;


  @override
  void initState() {
    super.initState();
    _company = widget.companyId == null ? Future.value(null) : _loadCompany(widget.companyId!);

  }

  Future<_CompanyData?> _loadCompany(int id) async {
    final company = await TradeDatabase.instance.getExhibitorById(id);
    if (company == null) return null;
    _scope = await TeamWorkspaceService().scopeKey();
    try {
      _canEdit = await ProductCaptureService.canWrite();
    } catch (_) {
      _canEdit = false;
    }
    _selectedCategories
      ..clear()
      ..addAll(SupplierCategoriesService.selected(company));
    _categoriesChanged = false;
    return _CompanyData(company, await TradeDatabase.instance.getContacts(id));
  }

  Future<void> _saveCategories() async {
    if (_scope == null || widget.companyId == null || _savingCategories) return;
    setState(() => _savingCategories = true);
    try {
      await SupplierCategoriesService.save(_scope!, widget.companyId!, Set.of(_selectedCategories));
      if (!mounted) return;
      setState(() => _company = _loadCompany(widget.companyId!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company categories saved. Use Sync to share them with your team.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save categories: $error')));
      }
    } finally {
      if (mounted) setState(() => _savingCategories = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.companyId != null) return _detail();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Companies')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          const FieldWorkspaceHeader(eyebrow: 'Supplier directory',
            title: 'Your business connections',
            subtitle: 'One company. Every contact, product and visit together.'),
          const SizedBox(height: 14),
          Expanded(child: DatabasePagedList(
            key: _directoryKey, loader: RecordPageService.companies,
            searchHint: 'Search company, contact, country or category',
            emptyMessage: 'Scan a business card to add your first company.',
            itemBuilder: (context, row) {
              final company = Exhibitor.fromMap(Map<String, dynamic>.from(row));
              final categories = SupplierCategoriesService.selected(company);
              return Card(clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                    SupplierContactsScreen(companyId: company.id, fairId: widget.fairId)));
                  if (mounted) await _directoryKey.currentState?.refresh();
                }, child: Padding(padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(backgroundColor: theme.colorScheme.secondaryContainer,
                        child: Icon(Icons.business_outlined, color: theme.colorScheme.secondary)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(company.name, style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${row['contact_count'] ?? 0} contacts${company.country.isEmpty ? '' : ' | ${company.country}'}',
                          style: theme.textTheme.bodySmall),
                      ])),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                    if (categories.isNotEmpty) ...[const SizedBox(height: 12),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final category in categories) Chip(label: Text(category))])],
                  ]))));
            },
          )),
        ])),
      ))),
    );
  }
  Widget _detail() => Scaffold(
    appBar: AppBar(title: const Text('Company workspace')),
    body: FutureBuilder<_CompanyData?>(
      future: _company,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load company: ${snapshot.error}'));
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) return const Center(child: Text('This company could not be found.'));
        return DefaultTabController(length: 4, child: SafeArea(child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960),
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: FieldWorkspaceHeader(eyebrow: 'Company workspace',
                  title: data.company.name,
                  subtitle: [if (data.company.country.isNotEmpty) data.company.country,
                    '${data.contacts.length} saved contacts'].join(' | '))),
              const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(text: 'Overview'), Tab(text: 'Contacts'),
                Tab(text: 'Products'), Tab(text: 'Visits'),
              ]),
              Expanded(child: TabBarView(children: [
                ListView(padding: const EdgeInsets.all(20), children: [
                  SupplierShortlistCard(scope: _scope!, company: data.company,
                    canEdit: _canEdit, fairId: widget.fairId),
                  const SizedBox(height: 16),
                  _categorySection(),
                ]),
                ListView(padding: const EdgeInsets.all(20), children: [
                  FieldWorkspaceSection(title: 'People at this company',
                    icon: Icons.people_outline,
                    subtitle: 'All business-card contacts are linked to this company.',
                    child: Column(children: [
                      if (data.contacts.isEmpty) const Text('No contacts saved yet.'),
                      for (final contact in data.contacts) Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(color: Theme.of(context).colorScheme.surfaceContainerLow,
                          child: Padding(padding: const EdgeInsets.all(16),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CircleAvatar(child: Text(contact.name.isEmpty ? '?' :
                                contact.name[0].toUpperCase())),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                Text(contact.name.isEmpty ? 'Contact' : contact.name,
                                  style: Theme.of(context).textTheme.titleMedium),
                                if (contact.designation.isNotEmpty) Text(contact.designation),
                                if (contact.phone.isNotEmpty) Padding(
                                  padding: const EdgeInsets.only(top: 8), child: SelectableText(contact.phone)),
                                if (contact.email.isNotEmpty) Padding(
                                  padding: const EdgeInsets.only(top: 4), child: SelectableText(contact.email)),
                              ])),
                            ])))),
                    ])),
                ]),
                ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
                  CompanyProductsSection(scope: _scope!, company: data.company,
                    canEdit: _canEdit, fairId: widget.fairId),
                ]),
                ListView(padding: const EdgeInsets.all(20), children: [
                  FieldWorkspaceSection(title: 'Factory & office visits', icon: Icons.event_outlined,
                    subtitle: 'Turn an exhibition conversation into a focused follow-up visit.',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Schedule appointments, continue workpads and keep discussions, products, evidence and agreed actions linked to this company.'),
                      const SizedBox(height: 18),
                      FilledButton.icon(icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Open visits & appointments'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CompanyVisitsScreen(company: data.company, fairId: widget.fairId)))),
                    ])),
                ]),
              ])),
            ]),
          ),
        )));
      },
    ),
  );

  Widget _categorySection() => FieldWorkspaceSection(
    title: 'Product categories', icon: Icons.category_outlined,
    subtitle: 'Select every category this company deals with. Categories are shared through Sync.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SupplierCategoryPicker(scope: _scope!, selected: _selectedCategories,
        enabled: _canEdit && !_savingCategories,
        onChanged: (categories) => setState(() {
          _selectedCategories..clear()..addAll(categories);
          _categoriesChanged = true;
        })),
      const SizedBox(height: 16),
      if (_canEdit) FilledButton.icon(
        onPressed: !_savingCategories && _categoriesChanged && _selectedCategories.isNotEmpty
            ? _saveCategories : null,
        icon: _savingCategories ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
        label: Text(_savingCategories ? 'Saving...' : 'Save categories')),
    ]),
  );
}
class _CompanyData {
  const _CompanyData(this.company, this.contacts);
  final Exhibitor company;
  final List<Contact> contacts;
}
