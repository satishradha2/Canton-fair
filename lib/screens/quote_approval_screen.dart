import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/cloud_sync_service.dart';
import '../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class QuoteApprovalScreen extends StatefulWidget {
  const QuoteApprovalScreen({super.key});

  @override
  State<QuoteApprovalScreen> createState() => _QuoteApprovalScreenState();
}

class _QuoteApprovalScreenState extends State<QuoteApprovalScreen> {
  final _db = TradeDatabase.instance;
  final _sync = CloudSyncService();
  String _filter = 'All';
  late Future<List<Map<String, dynamic>>> _quotes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _quotes = _db.getQuotesForApproval();

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return AppColors.teal;
      case 'Rejected':
        return AppColors.danger;
      case 'Changes requested':
        return AppColors.amber;
      case 'Pending approval':
        return AppColors.amber;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _setStatus(Map<String, dynamic> quote) async {
    var status = quote['approval_status'] as String? ?? 'Draft';
    final commentController =
        TextEditingController(text: quote['approval_comment'] as String? ?? '');
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review quote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Approval status'),
                items: const [
                  DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                  DropdownMenuItem(
                      value: 'Pending approval',
                      child: Text('Pending approval')),
                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  DropdownMenuItem(
                      value: 'Changes requested',
                      child: Text('Changes requested')),
                ],
                onChanged: (value) =>
                    setDialogState(() => status = value ?? status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: status == 'Rejected'
                      ? 'Reason for rejection'
                      : 'Review note',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    context, (status, commentController.text.trim())),
                child: const Text('Save review')),
          ],
        ),
      ),
    );
    commentController.dispose();
    if (result == null) return;
    if (result.$1 == 'Rejected' && result.$2.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a reason before rejecting a quote.')),
      );
      return;
    }
    final isFinal = result.$1 == 'Approved' || result.$1 == 'Rejected';
    final reviewer =
        Supabase.instance.client.auth.currentUser?.email ?? 'Local team member';
    await _db.update('quotes', quote['id'] as int, {
      'approval_status': result.$1,
      'approval_comment': result.$2,
      'approved_by': isFinal ? reviewer : '',
      'approved_at': isFinal ? DateTime.now().toIso8601String() : null,
    });
    await _db.logAudit('Quote ${result.$1.toLowerCase()}',
        '${quote['supplier_name'] ?? 'Supplier'} | ${quote['product_name'] ?? 'Product'}');
    if (mounted) setState(_load);
  }

  Future<void> _syncNow() async {
    try {
      final result = await _sync.syncTeamWorkspace();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Synced ${result.uploaded} uploaded, ${result.downloaded} downloaded.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sync: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote approvals'),
        actions: [
          IconButton(
              tooltip: 'Sync approvals',
              onPressed: _syncNow,
              icon: const Icon(Icons.sync)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _quotes,
        builder: (context, snapshot) {
          final quotes = snapshot.data ?? const <Map<String, dynamic>>[];
          final visible = _filter == 'All'
              ? quotes
              : quotes
                  .where((quote) =>
                      (quote['approval_status'] as String? ?? 'Draft') ==
                      _filter)
                  .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Review commercial quotes before committing to a supplier.',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'All',
                  'Draft',
                  'Pending approval',
                  'Approved',
                  'Rejected'
                ]
                    .map((status) => ChoiceChip(
                          label: Text(status),
                          selected: _filter == status,
                          onSelected: (_) => setState(() => _filter = status),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()))
              else if (visible.isEmpty)
                const EmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'No quotes to review',
                  message: 'Add a quote to a product, then review it here.',
                )
              else
                ...visible.map(_quoteCard),
            ],
          );
        },
      ),
    );
  }

  Widget _quoteCard(Map<String, dynamic> quote) {
    final status = quote['approval_status'] as String? ?? 'Draft';
    final validUntil = quote['valid_until'] as String?;
    final expiry = validUntil == null || validUntil.isEmpty
        ? 'No expiry'
        : 'Valid until ${validUntil.substring(0, validUntil.length > 10 ? 10 : validUntil.length)}';
    final price = quote['unit_price'] == null
        ? 'Price not recorded'
        : '${quote['unit_price']} ${quote['currency'] ?? 'USD'}';
    final note = quote['approval_comment'] as String? ?? '';
    final revision = quote['revision_number']?.toString() ?? '1';
    final revisionCount = quote['revision_count']?.toString() ?? '1';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        leading:
            Icon(Icons.request_quote_outlined, color: _statusColor(status)),
        title: Text(
            '${quote['supplier_name'] ?? 'Supplier'} - ${quote['product_name'] ?? 'Product'}'),
        subtitle: Text(
          '${quote['label'] ?? 'Quote'} | Revision $revision of $revisionCount | $price | MOQ ${quote['moq'] ?? '-'}\n$expiry${note.isEmpty ? '' : '\n$note'}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoChip(label: status, color: _statusColor(status)),
            IconButton(
                tooltip: 'Review quote',
                onPressed: () => _setStatus(quote),
                icon: const Icon(Icons.rate_review_outlined)),
          ],
        ),
      ),
    );
  }
}
