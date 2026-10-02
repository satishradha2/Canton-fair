import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/shortlist_service.dart';
import '../data/team_workspace_service.dart';
import 'product_capture_workspace_screen.dart';
import 'supplier_contacts_screen.dart';
import '../widgets/database_paged_list.dart';
import '../data/record_page_service.dart';
import '../data/field_work_repository.dart';
import '../widgets/record_search.dart';

class ShortlistsScreen extends StatefulWidget {
  const ShortlistsScreen({super.key});
  @override
  State<ShortlistsScreen> createState() => _ShortlistsScreenState();
}
class _ShortlistsScreenState extends State<ShortlistsScreen> {
  String? _scope;
  int _revision = 0;
  List<String> _categories = [];
  String? _supplierCategory, _productCategory;
  bool _canEdit = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      _scope = await TeamWorkspaceService().scopeKey();
      try { _canEdit = await ProductCaptureService.canWrite(); } catch (_) { _canEdit = false; }


      _categories = (await FieldWorkRepository().categories(_scope!)).map((row) => row['name'] as String).toList();
      await ProductCaptureService.checkScope(_scope!);
      if (mounted) setState(() => _revision++);
    } catch (error) { if (mounted) setState(() => _error = '$error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(Map<String, Object?> row, bool product) async {
    try {
      await ProductCaptureService.checkScope(_scope!);
      if (product) {
        final company = await TradeDatabase.instance.getExhibitorById(row['exhibitor_id'] as int);
        if (!mounted || company == null) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductCaptureWorkspaceScreen(
          scope: _scope!, company: company, productId: row['id'] as int, readOnly: !_canEdit)));
      } else {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierContactsScreen(companyId: row['id'] as int)));
      }
      if (mounted) await _load();
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }
  Future<void> _remove(Map<String, Object?> row, bool product) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Remove from shortlist?'), content: Text('${row['name']} will remain saved. No records or attachments will be deleted.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove from shortlist'))]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ShortlistService.set(scope: _scope!, id: row['id'] as int, product: product, selected: false);
      if (mounted) await _load();
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Widget _list(bool product) {
    final category = product ? _productCategory : _supplierCategory;
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      SearchableSelectionField<String>(key: ValueKey('$product:$category'), value: category,
        decoration: const InputDecoration(labelText: 'Category filter'), options: _categories, labelFor: (name) => name,
        onChanged: (value) => setState(() { if (product) { _productCategory = value; } else { _supplierCategory = value; } })),
      if (category != null) Align(alignment: Alignment.centerRight, child: TextButton(
        onPressed: () => setState(() { if (product) { _productCategory = null; } else { _supplierCategory = null; } }), child: const Text('All categories'))),
      const SizedBox(height: 12),
      Expanded(child: DatabasePagedList(key: ValueKey('list:$product:$category'), refreshToken: _revision,
        loader: (offset, limit, query) => RecordPageService.shortlist(product, offset, limit, query, category: category),
        searchHint: 'Search name, fair or selection reason',
        emptyMessage: 'No shortlisted ${product ? 'products' : 'suppliers'} yet.',
        itemBuilder: (context, row) {
          final details = ApprovalPolicy.jsonObject(row[product ? 'details_json' : 'field_capture_json']);
          final meta = ApprovalPolicy.jsonObject(details['shortlist']);
          return Card(child: InkWell(borderRadius: BorderRadius.circular(18),
            onTap: _busy ? null : () => _open(row, product), child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Icon(product ? Icons.inventory_2_outlined : Icons.business_outlined), const SizedBox(width: 10),
                Expanded(child: Text(row['name'].toString(), style: Theme.of(context).textTheme.titleMedium)),
                if (_canEdit) IconButton(tooltip: 'Remove from shortlist', icon: const Icon(Icons.bookmark_remove_outlined), onPressed: _busy ? null : () => _remove(row, product)),
              ]),
              if (product) Text(row['company_name'].toString()),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
                child: Text((meta['reason'] ?? '').toString().isEmpty ? 'No selection reason recorded.' : 'Why shortlisted: ${meta['reason']}')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if ((meta['fair'] ?? '').toString().isNotEmpty) Chip(label: Text(meta['fair'].toString())),
                if ((meta['selected_by'] ?? '').toString().isNotEmpty) Chip(label: Text('By ${meta['selected_by']}')),
              ]),
            ]))));
        })),
    ]));
  }  @override
  Widget build(BuildContext context) => DefaultTabController(length: 2, child: Scaffold(
    appBar: AppBar(title: const Text('Shortlists'), actions: [IconButton(onPressed: _busy ? null : _load,
      tooltip: 'Refresh', icon: const Icon(Icons.refresh))], bottom: const TabBar(tabs: [Tab(text: 'Suppliers'), Tab(text: 'Products')])),
    body: _busy ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) :
      Column(children: [const Padding(padding: EdgeInsets.all(16), child: Text('Interest, not approval. Use Sync to share selections with your team.')),
        Expanded(child: TabBarView(children: [_list(false), _list(true)]))]),
  ));
}
