import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SupplierComparisonScreen extends StatefulWidget {
  final List<Exhibitor> suppliers;

  const SupplierComparisonScreen({super.key, required this.suppliers});

  @override
  State<SupplierComparisonScreen> createState() =>
      _SupplierComparisonScreenState();
}

class _SupplierComparisonScreenState extends State<SupplierComparisonScreen> {
  final _db = TradeDatabase.instance;
  late final Future<Map<int, List<Product>>> _products;

  @override
  void initState() {
    super.initState();
    _products = _loadProducts();
  }

  Future<Map<int, List<Product>>> _loadProducts() async {
    final output = <int, List<Product>>{};
    for (final supplier in widget.suppliers) {
      if (supplier.id != null) {
        output[supplier.id!] = await _db.getProducts(supplier.id!);
      }
    }
    return output;
  }

  Color _decisionColor(String decision) {
    switch (decision) {
      case 'Shortlist':
        return AppColors.teal;
      case 'Reject':
        return AppColors.danger;
      default:
        return AppColors.amber;
    }
  }

  String _value(String value, {String empty = '-'}) =>
      value.trim().isEmpty ? empty : value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare suppliers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Compare selected suppliers side by side. Start with a Sourcing brief when you need to define buying requirements first.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          ...widget.suppliers.map((supplier) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _supplierCard(supplier),
              )),
          const SizedBox(height: 4),
          FutureBuilder<Map<int, List<Product>>>(
            future: _products,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()));
              }
              return _comparisonTable(snapshot.data ?? const {});
            },
          ),
        ],
      ),
    );
  }

  Widget _supplierCard(Exhibitor supplier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(supplier.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                InfoChip(
                    label: _value(supplier.booth, empty: 'Booth not set'),
                    icon: Icons.place_outlined),
                InfoChip(
                    label: _value(supplier.country, empty: 'Country not set'),
                    icon: Icons.public_outlined,
                    color: AppColors.primary),
                InfoChip(
                    label: supplier.decision,
                    icon: supplier.decision == 'Reject'
                        ? Icons.block_outlined
                        : Icons.flag_outlined,
                    color: _decisionColor(supplier.decision)),
                InfoChip(
                    label: '${supplier.decisionScore.toStringAsFixed(0)} / 100',
                    icon: Icons.grade_outlined,
                    color: AppColors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _productNames(List<Product> products) {
    if (products.isEmpty) return '-';
    return products.map((product) => product.name).take(3).join(', ');
  }

  Product? _lowestPrice(List<Product> products) {
    final priced = products.where((product) => product.quotedPrice != null);
    if (priced.isEmpty) return null;
    return priced.reduce((a, b) => a.quotedPrice! <= b.quotedPrice! ? a : b);
  }

  Product? _lowestMoq(List<Product> products) {
    final withMoq = products.where((product) => product.moq != null);
    if (withMoq.isEmpty) return null;
    return withMoq.reduce((a, b) => a.moq! <= b.moq! ? a : b);
  }

  String _bestLeadTime(List<Product> products) {
    final values = products
        .map((product) => product.leadTime)
        .where((leadTime) => leadTime.trim().isNotEmpty)
        .toList();
    if (values.isEmpty) return '-';
    values.sort((a, b) {
      final aDays = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '');
      final bDays = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '');
      return (aDays ?? 999999).compareTo(bDays ?? 999999);
    });
    return values.first;
  }

  Widget _comparisonTable(Map<int, List<Product>> productsBySupplier) {
    List<Product> productsFor(Exhibitor supplier) =>
        productsBySupplier[supplier.id] ?? const <Product>[];
    final rows = <(String, String Function(Exhibitor))>[
      ('Products', (supplier) => _productNames(productsFor(supplier))),
      (
        'Lowest quote',
        (supplier) {
          final product = _lowestPrice(productsFor(supplier));
          return product == null
              ? '-'
              : '${product.quotedPrice} ${product.priceCurrency}';
        }
      ),
      (
        'Lowest MOQ',
        (supplier) {
          final product = _lowestMoq(productsFor(supplier));
          return product == null ? '-' : '${product.moq}';
        }
      ),
      ('Best lead time', (supplier) => _bestLeadTime(productsFor(supplier))),
      (
        'Payment terms',
        (supplier) {
          final values = productsFor(supplier)
              .map((product) => product.paymentTerms)
              .where((terms) => terms.trim().isNotEmpty);
          return values.isEmpty ? '-' : values.first;
        }
      ),
      ('Rating', (supplier) => '${supplier.rating} / 5'),
      ('Quality', (supplier) => '${supplier.qualityScore}'),
      ('Response', (supplier) => '${supplier.responseSpeedScore}'),
      ('Trust', (supplier) => '${supplier.trustScore}'),
      ('MOQ fit', (supplier) => '${supplier.moqFitScore}'),
      ('Reliability', (supplier) => '${supplier.reliabilityScore}'),
      (
        'Visit status',
        (supplier) => supplier.visitedAt == null ? 'Not visited' : 'Visited'
      ),
      ('Notes', (supplier) => _value(supplier.contactCompanyNotes)),
    ];
    return SectionPanel(
      title: 'Decision comparison',
      subtitle: 'Scores are shown exactly as recorded by your team.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStatePropertyAll(AppColors.primary.withValues(alpha: 0.06)),
          columns: [
            const DataColumn(label: Text('Factor')),
            ...widget.suppliers.map((supplier) => DataColumn(
                label: SizedBox(
                    width: 118,
                    child: Text(supplier.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis)))),
          ],
          rows: rows
              .map((row) => DataRow(
                    cells: [
                      DataCell(Text(row.$1,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                      ...widget.suppliers.map((supplier) => DataCell(SizedBox(
                          width: 118,
                          child: Text(row.$2(supplier),
                              maxLines: 3, overflow: TextOverflow.ellipsis)))),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}
