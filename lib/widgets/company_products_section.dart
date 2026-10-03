import 'dart:io';
import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/database.dart';
import '../data/record_page_service.dart';
import '../models/models.dart';
import '../screens/product_capture_workspace_screen.dart';
import 'database_paged_list.dart';

class CompanyProductsSection extends StatefulWidget {
  const CompanyProductsSection({super.key, required this.scope, required this.company,
    required this.canEdit, this.fairId, this.visitKey});
  final String scope;
  final Exhibitor company;
  final bool canEdit;
  final int? fairId;
  final String? visitKey;
  @override
  State<CompanyProductsSection> createState() => _CompanyProductsSectionState();
}

class _CompanyProductsSectionState extends State<CompanyProductsSection> {
  int _revision = 0;
  Future<RecordPage> _load(int offset, int limit, String query) async {
    final page = await RecordPageService.products(widget.company.id!, offset, limit,
      query, visitKey: widget.visitKey);
    final rows = <Map<String, Object?>>[];
    for (final row in page.rows) {
      final attachments = await TradeDatabase.instance.getAttachments('product', row['id'] as int);
      final images = attachments.where((item) => item.kind == 'image').toList();
      String? cover;
      for (final image in images) {
        try {
          if (ApprovalPolicy.jsonObject(image.note)['cover'] == true) cover = image.path;
        } catch (_) { /* Legacy image label. */ }
      }
      rows.add({...row, 'details': ApprovalPolicy.jsonObject(row['details_json']),
        'cover': cover ?? (images.isEmpty ? null : images.first.path),
        'image_count': images.length,
        'audio_count': attachments.where((item) => item.kind == 'audio').length});
    }
    return RecordPage(rows, page.total);
  }
  Future<void> _open([int? product]) async {
    final editable = widget.canEdit && (product == null || await ApprovalPolicy.canEditRecord('products', product));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductCaptureWorkspaceScreen(
      scope: widget.scope, company: widget.company, productId: product, fairId: widget.fairId,
      readOnly: !editable, visitKey: widget.visitKey)));
    if (mounted) setState(() => _revision++);
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: 24),
    Text(widget.visitKey == null ? 'Products of interest' : 'Products captured / reviewed during this visit',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    const Text('Keep product photos, specifications, quotations and voice notes together.'),
    if (widget.canEdit) Padding(padding: const EdgeInsets.symmetric(vertical: 14),
      child: FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.add),
        label: const Text('Add product / resume draft'))),
    DatabasePagedList(pageSize: 20, shrinkWrap: true, refreshToken: _revision,
      loader: _load, searchHint: 'Search product, category, model or specifications',
      emptyMessage: 'No products captured yet. Add a product your team is interested in.',
      itemBuilder: (context, row) {
        final details = row['details'] as Map;
        return Card(clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: () => _open(row['id'] as int),
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (row['cover'] != null) ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(row['cover'] as String), height: 160, fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const SizedBox(height: 80,
                      child: Icon(Icons.image_outlined, size: 40)))),
                const SizedBox(height: 12),
                Text(row['name'] as String, style: Theme.of(context).textTheme.titleLarge),
                Text(row['category'] as String? ?? 'Category not assigned'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (row['moq'] != null) Chip(label: Text('MOQ ${row['moq']} ${details['quantity_unit'] ?? ''}')),
                  if (row['quoted_price'] != null) Chip(label: Text('${row['price_currency']} ${row['quoted_price']}')),
                  Chip(label: Text('${row['image_count']} images')),
                  Chip(label: Text('${row['audio_count']} voice notes')),
                ]),
                if ((details['captured_by'] ?? '').toString().isNotEmpty)
                  Text('Captured by ${details['captured_by']}'),
                if (details['ai_pending'] == true) const Text('Specification extraction pending'),
                const SizedBox(height: 8),
                const Text('Open product details', style: TextStyle(fontWeight: FontWeight.w700)),
              ]))));
      }),
  ]);
}
