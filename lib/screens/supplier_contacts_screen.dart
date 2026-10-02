import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/supplier_categories_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../widgets/supplier_category_picker.dart';
import '../widgets/company_products_section.dart';
import '../widgets/supplier_shortlist_card.dart';
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
  late Future<List<_CompanyData>> _companies;
  String? _scope;
  final Set<String> _selectedCategories = {};
  bool _canEdit = false;
  bool _savingCategories = false;
  bool _categoriesChanged = false;

  @override
  void initState() {
    super.initState();
    _company = widget.companyId == null ? Future.value(null) : _loadCompany(widget.companyId!);
    _companies = _loadCompanies();
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

  Future<List<_CompanyData>> _loadCompanies() async {
    final database = TradeDatabase.instance;
    final companies = await database.getExhibitors(null);
    final data = <_CompanyData>[];
    for (final company in companies) {
      data.add(_CompanyData(company, await database.getContacts(company.id!)));
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.companyId != null) return _detail();
    return Scaffold(
      appBar: AppBar(title: const Text('Companies and contacts')),
      body: FutureBuilder<List<_CompanyData>>(
        future: _companies,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not load companies: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final companies = snapshot.data!;
          if (companies.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No companies yet. Scan a business card to create the first company record.', textAlign: TextAlign.center)));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: companies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final data = companies[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.business_outlined)),
                  title: Text(data.company.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${data.contacts.length} contact${data.contacts.length == 1 ? '' : 's'}${data.company.country.isEmpty ? '' : ' • ${data.company.country}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierContactsScreen(companyId: data.company.id, fairId: widget.fairId))),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _detail() => Scaffold(
        appBar: AppBar(title: const Text('Company contacts')),
        body: FutureBuilder<_CompanyData?>(
          future: _company,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Could not load company: ${snapshot.error}'));
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data;
            if (data == null) return const Center(child: Text('This company could not be found.'));
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(data.company.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (data.company.country.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(data.company.country)),
                const SizedBox(height: 24),
                SupplierShortlistCard(scope: _scope!, company: data.company, canEdit: _canEdit, fairId: widget.fairId),
                Text('Contacts (${data.contacts.length})', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ...data.contacts.map((contact) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(contact.name.isEmpty ? '?' : contact.name[0].toUpperCase())),
                    title: Text(contact.name),
                    subtitle: Text([contact.designation, contact.phone, contact.email].where((value) => value.isNotEmpty).join('\n')),
                    isThreeLine: contact.designation.isNotEmpty && (contact.phone.isNotEmpty || contact.email.isNotEmpty),
                  ),
                )),
                const SizedBox(height: 24),
                Card(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Categories this company deals with',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Select all applicable product categories from Masters.'),
                    const SizedBox(height: 20),
                    SupplierCategoryPicker(
                      scope: _scope!,
                      selected: _selectedCategories,
                      enabled: _canEdit && !_savingCategories,
                      onChanged: (categories) => setState(() {
                        _selectedCategories..clear()..addAll(categories);
                        _categoriesChanged = true;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_canEdit) SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: !_savingCategories && _categoriesChanged && _selectedCategories.isNotEmpty ? _saveCategories : null,
                      icon: _savingCategories
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(_savingCategories ? 'Saving...' : 'Save categories'),
                    )),
                  ]),
                )),
                CompanyProductsSection(scope: _scope!, company: data.company, canEdit: _canEdit, fairId: widget.fairId),
                const SizedBox(height: 24),
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Factory & office visits', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Schedule appointments and keep each visit\'s discussions, products, evidence and agreed actions together.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(icon: const Icon(Icons.event_outlined), label: const Text('Visits & appointments'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyVisitsScreen(company: data.company, fairId: widget.fairId)))),
                ]))),
              ],
            );
          },
        ),
      );
}

class _CompanyData {
  const _CompanyData(this.company, this.contacts);
  final Exhibitor company;
  final List<Contact> contacts;
}
