import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/shortlist_service.dart';
import '../models/models.dart';

class SupplierShortlistCard extends StatefulWidget {
  const SupplierShortlistCard({super.key, required this.scope, required this.company,
    required this.canEdit, this.fairId});
  final String scope;
  final Exhibitor company;
  final bool canEdit;
  final int? fairId;
  @override
  State<SupplierShortlistCard> createState() => _SupplierShortlistCardState();
}

class _SupplierShortlistCardState extends State<SupplierShortlistCard> {
  late bool _selected;
  late TextEditingController _reason;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _selected = widget.company.shortlisted;
    final details = ApprovalPolicy.jsonObject(widget.company.fieldCaptureJson);
    _reason = TextEditingController(text: ApprovalPolicy.jsonObject(details['shortlist'])['reason']?.toString() ?? '');
  }
  @override
  void dispose() { _reason.dispose(); super.dispose(); }
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ShortlistService.set(scope: widget.scope, id: widget.company.id!, product: false,
        selected: _selected, reason: _reason.text, fairId: widget.fairId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier shortlist saved. Use Sync to share with your team.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save shortlist: $error')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Shortlist supplier'),
      subtitle: const Text('Supplier interest only. Product selections are separate.'), value: _selected,
      onChanged: widget.canEdit && !_busy ? (value) => setState(() => _selected = value) : null),
    if (_selected) TextField(controller: _reason, enabled: widget.canEdit && !_busy,
      decoration: const InputDecoration(labelText: 'Shortlist reason (optional)', border: OutlineInputBorder())),
    if (widget.canEdit) Align(alignment: Alignment.centerRight, child: TextButton(
      onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save shortlist selection'))),
  ])));
}
