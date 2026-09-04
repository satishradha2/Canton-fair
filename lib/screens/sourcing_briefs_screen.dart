import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SourcingBriefsScreen extends StatefulWidget {
  const SourcingBriefsScreen({super.key});

  @override
  State<SourcingBriefsScreen> createState() => _SourcingBriefsScreenState();
}

class _SourcingBriefsScreenState extends State<SourcingBriefsScreen> {
  final _db = TradeDatabase.instance;
  late Future<List<SourcingBrief>> _briefs;

  @override
  void initState() {
    super.initState();
    _briefs = _db.getSourcingBriefs();
  }

  void _reload() => setState(() => _briefs = _db.getSourcingBriefs());

  Future<void> _edit([SourcingBrief? brief]) async {
    final name = TextEditingController(text: brief?.name ?? '');
    final category = TextEditingController(text: brief?.category ?? '');
    final price =
        TextEditingController(text: brief?.targetPrice?.toString() ?? '');
    final moq = TextEditingController(text: brief?.targetMoq?.toString() ?? '');
    final certificates =
        TextEditingController(text: brief?.requiredCertifications ?? '');
    final notes = TextEditingController(text: brief?.notes ?? '');
    final result = await showDialog<SourcingBrief>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(brief == null ? 'New sourcing brief' : 'Edit sourcing brief'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'What are you sourcing?')),
            TextField(
                controller: category,
                decoration:
                    const InputDecoration(labelText: 'Category / keywords')),
            TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Target unit price (optional)')),
            TextField(
                controller: moq,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Target MOQ (optional)')),
            TextField(
                controller: certificates,
                decoration:
                    const InputDecoration(labelText: 'Required certificates')),
            TextField(
                controller: notes,
                minLines: 3,
                maxLines: 5,
                decoration:
                    const InputDecoration(labelText: 'Must-haves and notes')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  SourcingBrief(
                    id: brief?.id,
                    tripId: brief?.tripId,
                    name: name.text.trim(),
                    category: category.text.trim(),
                    targetPrice: double.tryParse(price.text.trim()),
                    targetMoq: double.tryParse(moq.text.trim()),
                    requiredCertifications: certificates.text.trim(),
                    notes: notes.text.trim(),
                    createdAt: brief?.createdAt ?? DateTime.now(),
                  )),
              child: const Text('Save brief')),
        ],
      ),
    );
    name.dispose();
    category.dispose();
    price.dispose();
    moq.dispose();
    certificates.dispose();
    notes.dispose();
    if (result == null || result.name.isEmpty) return;
    if (brief == null) {
      await _db.saveSourcingBrief(result);
    } else {
      await _db.updateSourcingBrief(result);
    }
    _reload();
  }

  int _matchScore(
      SourcingBrief brief, Exhibitor supplier, List<Product> products) {
    var score = 0;
    final category = brief.category.toLowerCase();
    if (category.isNotEmpty &&
        (supplier.category.toLowerCase().contains(category) ||
            products.any((p) => p.name.toLowerCase().contains(category)))) {
      score += 30;
    }
    if (brief.targetPrice == null ||
        products.any((p) =>
            p.quotedPrice != null && p.quotedPrice! <= brief.targetPrice!)) {
      score += 20;
    }
    if (brief.targetMoq == null ||
        products.any((p) => p.moq != null && p.moq! <= brief.targetMoq!)) {
      score += 20;
    }
    final certificates =
        _certificates(supplier.verificationJson).join(' ').toLowerCase();
    final wanted = brief.requiredCertifications.toLowerCase();
    if (wanted.isEmpty || certificates.contains(wanted)) {
      score += 15;
    }
    if (supplier.decision == 'Shortlist') {
      score += 10;
    }
    if (supplier.visitedAt != null) {
      score += 5;
    }
    return score;
  }

  List<String> _certificates(String raw) {
    try {
      final data = jsonDecode(raw) as Map;
      return (data['certificates'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item['type']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _showMatches(SourcingBrief brief) async {
    final suppliers = await _db.getExhibitors(null);
    final allProducts =
        (await _db.queryAll('products')).map(Product.fromMap).toList();
    final matches = suppliers
        .map((supplier) {
          final products =
              allProducts.where((p) => p.exhibitorId == supplier.id).toList();
          return (
            supplier: supplier,
            score: _matchScore(brief, supplier, products)
          );
        })
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Supplier matches',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
              'Match score is based on your category, price, MOQ, certificates, shortlist, and visit evidence.'),
          const SizedBox(height: 12),
          if (matches.isEmpty)
            const ListTile(
                title: Text('No matching suppliers yet'),
                subtitle: Text(
                    'Capture suppliers and products at the fair to populate this shortlist.')),
          ...matches.map((item) => ListTile(
                leading: CircleAvatar(child: Text('${item.score}')),
                title: Text(item.supplier.name),
                subtitle: Text([item.supplier.booth, item.supplier.category]
                    .where((item) => item.isNotEmpty)
                    .join(' | ')),
              )),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SourcingBrief>>(
        future: _briefs,
        builder: (context, snapshot) => EnterprisePage(
          title: 'Sourcing briefs',
          subtitle:
              'Define what you need to buy. Use Compare suppliers to evaluate chosen suppliers side by side.',
          actions: [
            IconButton(
                tooltip: 'Add sourcing brief',
                onPressed: _edit,
                icon: const Icon(Icons.add))
          ],
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: CircularProgressIndicator())
            else if ((snapshot.data ?? const []).isEmpty)
              SectionPanel(
                  title: 'Start with a buying need',
                  subtitle:
                      'Define the product, price, MOQ, and compliance requirements before walking the halls.',
                  child: FilledButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.add),
                      label: const Text('Create sourcing brief')))
            else
              ...snapshot.data!.map((brief) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SectionPanel(
                      title: brief.name,
                      subtitle: [
                        brief.category,
                        if (brief.targetPrice != null)
                          'Target ${brief.targetPrice}',
                        if (brief.targetMoq != null) 'MOQ ${brief.targetMoq}'
                      ].where((item) => item.isNotEmpty).join(' | '),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') _edit(brief);
                          if (value == 'delete') {
                            await _db.deleteSourcingBrief(brief.id!);
                            _reload();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete'))
                        ],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (brief.requiredCertifications.isNotEmpty)
                              InfoChip(
                                  label:
                                      'Certificates: ${brief.requiredCertifications}',
                                  icon: Icons.verified_outlined,
                                  color: AppColors.teal),
                            if (brief.notes.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(brief.notes)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: () => _showMatches(brief),
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('See supplier matches')),
                          ]),
                    ),
                  )),
          ],
        ),
      );
}
