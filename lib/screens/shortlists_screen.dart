import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/shortlist_service.dart';
import '../data/team_workspace_service.dart';
import 'product_capture_workspace_screen.dart';
import 'supplier_contacts_screen.dart';

class ShortlistsScreen extends StatefulWidget {
  const ShortlistsScreen({super.key});
  @override
  State<ShortlistsScreen> createState() => _ShortlistsScreenState();
}
class _ShortlistsScreenState extends State<ShortlistsScreen> {
  String? _scope;
  bool _canEdit = false;
  bool _busy = false;
  String? _error;
  List<Map<String, Object?>> _suppliers = [], _products = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      _scope = await TeamWorkspaceService().scopeKey();
      try { _canEdit = await ProductCaptureService.canWrite(); } catch (_) { _canEdit = false; }
      final suppliers = await ShortlistService.entries(false);
      final products = await ShortlistService.entries(true);
      await ProductCaptureService.checkScope(_scope!);
      if (mounted) setState(() { _suppliers = suppliers; _products = products; });
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
    final rows = product ? _products : _suppliers;
    if (rows.isEmpty) return Center(child: Text('No shortlisted ${product ? 'products' : 'suppliers'} yet.'));
    return ListView.separated(padding: const EdgeInsets.all(20), itemCount: rows.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12), itemBuilder: (context, index) {
        final row = rows[index];
        final details = ApprovalPolicy.jsonObject(row[product ? 'details_json' : 'field_capture_json']);
        final meta = ApprovalPolicy.jsonObject(details['shortlist']);
        final date = DateTime.tryParse(meta['selected_at']?.toString() ?? '')?.toLocal();
        return Card(child: ListTile(isThreeLine: true,
          leading: Icon(product ? Icons.inventory_2_outlined : Icons.business_outlined),
          title: Text(row['name'].toString()),
          subtitle: Text([
            if (product) row['company_name'].toString(),
            if ((meta['reason'] ?? '').toString().isNotEmpty) meta['reason'].toString(),
            if ((meta['fair'] ?? '').toString().isNotEmpty) 'Fair: ${meta['fair']}',
            if (date != null) 'Selected: ${date.toString().split('.').first}',
            if ((meta['selected_by'] ?? '').toString().isNotEmpty) 'By: ${meta['selected_by']}',
          ].join('\n')),
          onTap: _busy ? null : () => _open(row, product),
          trailing: _canEdit ? IconButton(tooltip: 'Remove from shortlist', icon: const Icon(Icons.bookmark_remove_outlined),
            onPressed: _busy ? null : () => _remove(row, product)) : null));
      });
  }
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 2, child: Scaffold(
    appBar: AppBar(title: const Text('Shortlists'), actions: [IconButton(onPressed: _busy ? null : _load,
      tooltip: 'Refresh', icon: const Icon(Icons.refresh))], bottom: const TabBar(tabs: [Tab(text: 'Suppliers'), Tab(text: 'Products')])),
    body: _busy ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) :
      Column(children: [const Padding(padding: EdgeInsets.all(16), child: Text('Interest, not approval. Use Sync to share selections with your team.')),
        Expanded(child: TabBarView(children: [_list(false), _list(true)]))]),
  ));
}
