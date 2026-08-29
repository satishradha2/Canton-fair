import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../data/database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

enum _ProductSortField { score, price, moq, leadTime }

class ShortlistScreen extends StatefulWidget {
  const ShortlistScreen({super.key});

  @override
  State<ShortlistScreen> createState() => _ShortlistScreenState();
}

class _ShortlistScreenState extends State<ShortlistScreen> {
  final db = TradeDatabase.instance;
  Future<List<Exhibitor>> _shortlistExhibitors = Future.value([]);
  late Future<List<Product>> _shortlistProducts;
  final _minScoreController = TextEditingController(text: '0');
  double _minScore = 0.0;
  int _shortlistProductTotal = 0;
  int _shortlistProductVisible = 0;
  _ProductSortField _sortField = _ProductSortField.score;
  bool _sortAscending = false;
  bool _tripDayOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minScoreController.dispose();
    super.dispose();
  }

  void _load() {
    _shortlistProducts = _loadShortlistedProducts();
    _shortlistExhibitors = _loadExhibitors();
  }

  Future<List<Product>> _loadShortlistedProducts() async {
    final rows = await db.getShortlistedProductsWithTrip();
    final tripIds = _tripDayOnly ? await _loadTripDayIds() : null;

    if (tripIds != null && tripIds.isEmpty) {
      _shortlistProductTotal = 0;
      _shortlistProductVisible = 0;
      return [];
    }

    final effectiveRows = tripIds == null
        ? rows
        : rows.where((r) => tripIds.contains(r['trip_id'] as int?)).toList();
    final products = effectiveRows.map((row) {
      return Product(
        id: row['id'] as int?,
        exhibitorId: row['exhibitor_id'] as int,
        name: row['name'] as String,
        modelCode: row['model_code'] as String? ?? '',
        specs: row['specs'] as String? ?? '',
        moq: row['moq'] != null ? (row['moq'] as num).toDouble() : null,
        quotedPrice: row['quoted_price'] != null
            ? (row['quoted_price'] as num).toDouble()
            : null,
        priceCurrency: row['price_currency'] as String? ?? 'USD',
        leadTime: row['lead_time'] as String? ?? '',
        paymentTerms: row['payment_terms'] as String? ?? '',
        shortlisted: true,
        rating: row['rating'] as int? ?? 0,
      );
    }).toList();

    _shortlistProductTotal = products.length;
    final filtered = _minScore <= 0
        ? List<Product>.from(products)
        : products.where((p) => _shortlistScore(p) >= _minScore).toList();
    filtered.sort(_compareProducts);
    _shortlistProductVisible = filtered.length;
    return filtered;
  }

  Future<Set<int>> _loadTripDayIds() async {
    final trips = await db.getTrips();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activeTripIds = <int>{};

    for (final trip in trips) {
      if (trip.id == null || trip.startDate == null || trip.endDate == null)
        continue;
      final start = DateTime(
          trip.startDate!.year, trip.startDate!.month, trip.startDate!.day);
      final end =
          DateTime(trip.endDate!.year, trip.endDate!.month, trip.endDate!.day);
      if (!today.isBefore(start) && !today.isAfter(end)) {
        activeTripIds.add(trip.id!);
      }
    }

    return activeTripIds;
  }

  double _shortlistScore(Product p) {
    final ratingScore = (p.rating / 5.0) * 40.0;
    final priceScore =
        p.quotedPrice == null ? 0.0 : 1000.0 / (1.0 + p.quotedPrice!.abs());
    final moqScore = p.moq == null ? 0.0 : 30.0 / (1.0 + p.moq!);
    final leadMatch = RegExp(r'\d+').firstMatch(p.leadTime);
    final lead =
        leadMatch == null ? null : double.tryParse(leadMatch.group(0)!);
    final leadScore = lead == null ? 0.0 : 15.0 / (1.0 + lead);
    return ratingScore + priceScore + moqScore + leadScore;
  }

  double _leadTimeValue(Product p) {
    final leadMatch = RegExp(r'\d+').firstMatch(p.leadTime);
    if (leadMatch == null) return double.infinity;
    return double.tryParse(leadMatch.group(0)!) ?? double.infinity;
  }

  String _shortlistScoreBand(double score) {
    if (score >= 60) return 'A';
    if (score >= 45) return 'B';
    if (score >= 30) return 'C';
    return 'D';
  }

  Color _shortlistScoreBandColor(double score) {
    if (score >= 60) return Colors.green;
    if (score >= 45) return Colors.orange;
    if (score >= 30) return Colors.blue;
    return Colors.grey;
  }

  bool _isPresetActive(double preset) {
    if (preset == 0) return _minScore <= 0;
    return _minScore == preset;
  }

  int _compareProducts(Product a, Product b) {
    late int cmp;
    switch (_sortField) {
      case _ProductSortField.price:
        final aPrice = a.quotedPrice ?? double.infinity;
        final bPrice = b.quotedPrice ?? double.infinity;
        cmp = aPrice.compareTo(bPrice);
        break;
      case _ProductSortField.moq:
        final aMoq = a.moq == null ? double.infinity : a.moq!.toDouble();
        final bMoq = b.moq == null ? double.infinity : b.moq!.toDouble();
        cmp = aMoq.compareTo(bMoq);
        break;
      case _ProductSortField.leadTime:
        cmp = _leadTimeValue(a).compareTo(_leadTimeValue(b));
        break;
      case _ProductSortField.score:
        cmp = _shortlistScore(b).compareTo(_shortlistScore(a));
        break;
    }

    if (_sortField == _ProductSortField.score) {
      if (cmp == 0) cmp = _shortlistScore(a).compareTo(_shortlistScore(b));
      cmp = _sortAscending ? -cmp : cmp;
      return cmp;
    }

    return _sortAscending ? cmp : -cmp;
  }

  String _sortFieldLabel() {
    switch (_sortField) {
      case _ProductSortField.score:
        return 'Score';
      case _ProductSortField.price:
        return 'Price';
      case _ProductSortField.moq:
        return 'MOQ';
      case _ProductSortField.leadTime:
        return 'Lead time';
    }
  }

  Future<List<Exhibitor>> _loadExhibitors() async {
    final rows = await db.queryAll('exhibitors',
        where: 'shortlisted = 1', orderBy: 'rating DESC');
    final tripIds = _tripDayOnly ? await _loadTripDayIds() : null;
    if (tripIds != null && tripIds.isEmpty) return [];

    final effectiveRows = tripIds == null
        ? rows
        : rows
            .where((row) => tripIds.contains(row['trip_id'] as int?))
            .toList();
    return effectiveRows.map((e) => Exhibitor.fromMap(e)).toList();
  }

  Future<void> _toggleExhibitorShortlist(Exhibitor e) async {
    await db
        .update('exhibitors', e.id!, {'shortlisted': e.shortlisted ? 0 : 1});
    _load();
    setState(() {});
  }

  Future<void> _toggleProductShortlist(Product p) async {
    await db.update('products', p.id!, {'shortlisted': p.shortlisted ? 0 : 1});
    _load();
    setState(() {});
  }

  Future<Map<int, Map<String, dynamic>>> _loadShortlistSupplierMap() async {
    final rows = await db.queryAll('exhibitors', where: 'shortlisted = 1');
    final map = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is int) {
        map[id] = row;
      }
    }
    return map;
  }

  Future<List<List<dynamic>>> _buildCsvRows() async {
    final products = await _shortlistProducts;
    final suppliers = await _loadShortlistSupplierMap();
    final rows = <List<dynamic>>[
      [
        'Type',
        'ID',
        'Supplier',
        'Booth',
        'Product',
        'Model',
        'Price',
        'Currency',
        'MOQ',
        'Lead time',
        'Score',
        'Tier'
      ],
    ];
    final seenSuppliers = <int>{};

    for (final p in products) {
      final supplier = suppliers[p.exhibitorId];
      final supplierId = supplier?['id'] as int?;
      final supplierName = supplier?['name']?.toString() ?? 'Unknown supplier';
      final supplierBooth = supplier?['booth']?.toString() ?? '';
      final score = _shortlistScore(p);
      final band = _shortlistScoreBand(score);

      if (supplierId != null && seenSuppliers.add(supplierId)) {
        rows.add([
          'Supplier',
          supplierId,
          supplierName,
          supplierBooth,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      }

      rows.add([
        'Product',
        p.id,
        supplierName,
        supplierBooth,
        p.name,
        p.modelCode,
        p.quotedPrice ?? '',
        p.priceCurrency,
        p.moq ?? '',
        p.leadTime,
        score.toStringAsFixed(2),
        'Tier $band',
      ]);
    }

    if (rows.length == 1) {
      rows.add([
        'No shortlisted products meet current filters.',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        ''
      ]);
    }

    return rows;
  }

  Future<String> _writeCsv(List<List<dynamic>> rows, String filename) async {
    final docs = await getTemporaryDirectory();
    final path = '${docs.path}/$filename';
    final file = File(path);
    final csvData = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csvData, encoding: utf8);
    return file.path;
  }

  Future<void> _exportShortlistCsv() async {
    try {
      final rows = await _buildCsvRows();
      final filter = _minScore <= 0 ? 'none' : _minScore.toStringAsFixed(0);
      final direction = _sortAscending ? 'low_to_high' : 'high_to_low';
      final path = await _writeCsv(
        rows,
        'canton_fair_shortlist_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await Share.shareXFiles(
        [XFile(path)],
        text:
            'Canton Fair shortlist export (filter: $filter, sort: ${_sortFieldLabel()} $direction)',
      );
      _showExportSnack('Shortlist CSV exported.');
    } catch (error) {
      _showExportSnack('Export failed: $error');
    }
  }

  Future<void> _exportShortlistPdf() async {
    try {
      final products = await _shortlistProducts;
      final suppliers = await _loadShortlistSupplierMap();
      final filter = _minScore <= 0
          ? 'No minimum score filter'
          : 'Minimum score >= ${_minScore.toStringAsFixed(0)}';
      final sortDescription =
          '${_sortFieldLabel()} (${_sortAscending ? 'Low to High' : 'High to Low'})';
      final now = DateTime.now().toLocal().toIso8601String();
      final doc = pw.Document();

      final data = products.map((p) {
        final supplier = suppliers[p.exhibitorId];
        final score = _shortlistScore(p);
        return [
          p.name,
          supplier?['name']?.toString() ?? 'Unknown supplier',
          supplier?['booth']?.toString() ?? '',
          p.quotedPrice == null ? '-' : p.quotedPrice.toString(),
          p.priceCurrency,
          p.moq == null ? '-' : p.moq.toString(),
          p.leadTime.isEmpty ? '-' : p.leadTime,
          score.toStringAsFixed(2),
          _shortlistScoreBand(score),
          p.id?.toString() ?? '',
        ];
      }).toList();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (context) {
            final widgets = <pw.Widget>[
              pw.Text(
                'Canton Fair Shortlist Export',
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Generated: $now'),
              pw.SizedBox(height: 12),
              pw.Text('Filter: $filter'),
              pw.Text('Sort: $sortDescription'),
              pw.Text('Items: ${products.length}'),
              pw.SizedBox(height: 12),
            ];

            if (data.isEmpty) {
              widgets.add(
                  pw.Text('No shortlisted products match current filters.'));
              return widgets;
            }

            widgets.add(
              pw.Table.fromTextArray(
                headers: const [
                  'Product',
                  'Supplier',
                  'Booth',
                  'Price',
                  'Currency',
                  'MOQ',
                  'Lead time',
                  'Score',
                  'Tier',
                  'Product ID',
                ],
                data: data.cast<List<String>>(),
                border: pw.TableBorder.all(),
                headerStyle:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignments: const {0: pw.Alignment.centerLeft},
              ),
            );

            return widgets;
          },
        ),
      );

      final out = File(
          '${(await getTemporaryDirectory()).path}/canton_fair_shortlist_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await out.writeAsBytes(await doc.save());
      await Share.shareXFiles(
        [XFile(out.path)],
        text: 'Canton Fair shortlist PDF (${products.length} products)',
      );
      _showExportSnack('Shortlist PDF exported.');
    } catch (error) {
      _showExportSnack('Export failed: $error');
    }
  }

  void _showExportSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _applyMinScoreFilter(String value) {
    final parsed = double.tryParse(value.trim());
    _minScore = parsed == null || parsed < 0 ? 0.0 : parsed;
    _load();
    setState(() {});
  }

  void _setMinScorePreset(double value) {
    _minScore = value;
    _minScoreController.text = value.toStringAsFixed(0);
    _load();
    setState(() {});
  }

  void _setTripDayOnly(bool value) {
    _tripDayOnly = value;
    _load();
    setState(() {});
  }

  void _setSortField(_ProductSortField field) {
    _sortField = field;
    _load();
    setState(() {});
  }

  void _toggleSortDirection() {
    _sortAscending = !_sortAscending;
    _load();
    setState(() {});
  }

  String get _filterSummaryText {
    final tripScope = _tripDayOnly ? 'Active trip today' : 'All trips';
    if (_minScore <= 0) {
      return '$tripScope | No score filter | Showing $_shortlistProductVisible of $_shortlistProductTotal shortlisted products';
    }
    return '$tripScope | Score >= ${_minScore.toStringAsFixed(0)} | Showing $_shortlistProductVisible of $_shortlistProductTotal shortlisted products';
  }

  String get _sortDirectionLabel {
    return _sortAscending ? 'Low to High' : 'High to Low';
  }

  Widget _legendChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_load),
      child: EnterprisePage(
        title: 'Shortlist Workspace',
        subtitle:
            'Compare suppliers and products using score, quote, MOQ, lead time, and trip timing.',
        actions: [
          ElevatedButton.icon(
              onPressed: _exportShortlistCsv,
              icon: const Icon(Icons.table_view),
              label: const Text('CSV')),
          TextButton.icon(
              onPressed: _exportShortlistPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF')),
        ],
        children: [
          SectionPanel(
            title: 'Controls',
            subtitle: _filterSummaryText,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      avatar: const Icon(Icons.today, size: 18),
                      label: const Text('Trip day only'),
                      selected: _tripDayOnly,
                      onSelected: _setTripDayOnly,
                    ),
                    ChoiceChip(
                        label: const Text('>= 10'),
                        selected: _isPresetActive(10),
                        onSelected: (_) => _setMinScorePreset(10)),
                    ChoiceChip(
                        label: const Text('>= 20'),
                        selected: _isPresetActive(20),
                        onSelected: (_) => _setMinScorePreset(20)),
                    ChoiceChip(
                        label: const Text('>= 30'),
                        selected: _isPresetActive(30),
                        onSelected: (_) => _setMinScorePreset(30)),
                    ChoiceChip(
                        label: const Text('>= 40'),
                        selected: _isPresetActive(40),
                        onSelected: (_) => _setMinScorePreset(40)),
                    ChoiceChip(
                        label: const Text('Clear'),
                        selected: _isPresetActive(0),
                        onSelected: (_) => _setMinScorePreset(0)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 112,
                      child: TextField(
                        controller: _minScoreController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Min score'),
                        onChanged: _applyMinScoreFilter,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                              label: const Text('Score'),
                              selected: _sortField == _ProductSortField.score,
                              onSelected: (_) =>
                                  _setSortField(_ProductSortField.score)),
                          ChoiceChip(
                              label: const Text('Price'),
                              selected: _sortField == _ProductSortField.price,
                              onSelected: (_) =>
                                  _setSortField(_ProductSortField.price)),
                          ChoiceChip(
                              label: const Text('MOQ'),
                              selected: _sortField == _ProductSortField.moq,
                              onSelected: (_) =>
                                  _setSortField(_ProductSortField.moq)),
                          ChoiceChip(
                              label: const Text('Lead time'),
                              selected:
                                  _sortField == _ProductSortField.leadTime,
                              onSelected: (_) =>
                                  _setSortField(_ProductSortField.leadTime)),
                          InputChip(
                            label: Text(_sortDirectionLabel),
                            avatar: Icon(_sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward),
                            onPressed: _toggleSortDirection,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _legendChip('Tier A: 60+', Colors.green),
                    _legendChip('Tier B: 45-59', Colors.orange),
                    _legendChip('Tier C: 30-44', Colors.blue),
                    _legendChip('Tier D: <30', Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: 'Shortlisted suppliers',
            child: FutureBuilder<List<Exhibitor>>(
              future: _shortlistExhibitors,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return EmptyState(
                    icon: Icons.business_outlined,
                    title: 'No shortlisted suppliers',
                    message: _tripDayOnly
                        ? 'No suppliers for an active trip today.'
                        : 'Star suppliers from Captures to build this list.',
                  );
                }
                return Column(
                  children: snap.data!.map((e) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          'Booth ${e.booth.isEmpty ? "-" : e.booth}  |  Rating ${e.rating}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.star_border),
                        tooltip: 'Remove from shortlist',
                        onPressed: () => _toggleExhibitorShortlist(e),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: 'Shortlisted products',
            child: FutureBuilder<List<Product>>(
              future: _shortlistProducts,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No shortlisted products',
                    message: _tripDayOnly
                        ? 'No products for an active trip today.'
                        : 'Shortlist products from supplier records to compare them here.',
                  );
                }
                return Column(
                    children: snap.data!.map(_productComparisonCard).toList());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _productComparisonCard(Product p) {
    final score = _shortlistScore(p);
    final bandColor = _shortlistScoreBandColor(score);
    final band = _shortlistScoreBand(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoChip(
                        label: p.quotedPrice == null
                            ? 'No price'
                            : '${p.quotedPrice} ${p.priceCurrency}',
                        icon: Icons.payments),
                    InfoChip(
                        label: 'MOQ ${p.moq ?? "-"}',
                        icon: Icons.inventory_2,
                        color: AppColors.teal),
                    InfoChip(
                        label: p.leadTime.isEmpty ? 'No lead time' : p.leadTime,
                        icon: Icons.schedule,
                        color: AppColors.amber),
                    InfoChip(
                        label: 'Tier $band',
                        icon: Icons.grade,
                        color: bandColor),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(score.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove shortlist',
                onPressed: () => _toggleProductShortlist(p),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
