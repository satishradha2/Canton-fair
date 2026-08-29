import 'package:flutter/material.dart';
import '../data/database.dart';
import '../models/models.dart';

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
    _shortlistProducts = db.getShortlistedProducts().then((rows) {
      _shortlistProductTotal = rows.length;
      final filtered =
          _minScore <= 0 ? List<Product>.from(rows) : rows.where((p) => _shortlistScore(p) >= _minScore).toList();
      filtered.sort(_compareProducts);
      _shortlistProductVisible = filtered.length;
      return filtered;
    });
    _shortlistExhibitors = _loadExhibitors();
  }

  double _shortlistScore(Product p) {
    final ratingScore = (p.rating / 5.0) * 40.0;
    final priceScore = p.quotedPrice == null ? 0.0 : 1000.0 / (1.0 + p.quotedPrice!.abs());
    final moqScore = p.moq == null ? 0.0 : 30.0 / (1.0 + p.moq!);
    final leadMatch = RegExp(r'\d+').firstMatch(p.leadTime);
    final lead = leadMatch == null ? null : double.tryParse(leadMatch.group(0)!);
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
      default:
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

  Future<List<Exhibitor>> _loadExhibitors() async {
    final rows = await db.queryAll('exhibitors', where: 'shortlisted = 1', orderBy: 'rating DESC');
    return rows.map((e) => Exhibitor.fromMap(e)).toList();
  }

  Future<void> _toggleExhibitorShortlist(Exhibitor e) async {
    await db.update('exhibitors', e.id!, {'shortlisted': e.shortlisted ? 0 : 1});
    _load();
    setState(() {});
  }

  Future<void> _toggleProductShortlist(Product p) async {
    await db.update('products', p.id!, {'shortlisted': p.shortlisted ? 0 : 1});
    _load();
    setState(() {});
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
    if (_minScore <= 0) {
      return 'No score filter active • Showing $_shortlistProductVisible of $_shortlistProductTotal shortlisted products';
    }
    return 'Filtering score >= ${_minScore.toStringAsFixed(0)} • Showing $_shortlistProductVisible of $_shortlistProductTotal shortlisted products';
  }

  String get _sortDirectionLabel {
    return _sortAscending ? 'Low → High' : 'High → Low';
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
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Shortlist workspace', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              title: Text('How comparison works'),
              subtitle: Text(
                'Products are ranked by shortlist score (rating, price, MOQ, lead time). '
                'Suppliers are ranked by manual rating.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Shortlisted Suppliers', style: TextStyle(fontWeight: FontWeight.bold)),
          FutureBuilder<List<Exhibitor>>(
            future: _shortlistExhibitors,
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No suppliers shortlisted yet.'),
                );
              }
              return Column(
                children: snap.data!.map((e) {
                  return Card(
                    child: ListTile(
                      title: Text(e.name),
                      subtitle: Text('Booth ${e.booth} | Rating ${e.rating}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.star_border),
                        tooltip: 'Remove from shortlist',
                        onPressed: () => _toggleExhibitorShortlist(e),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('Shortlisted Products', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Min score:'),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _minScoreController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.all(8),
                  ),
                  onChanged: _applyMinScoreFilter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('>= 10'),
                selected: _isPresetActive(10),
                onSelected: (selected) => _setMinScorePreset(10),
              ),
              ChoiceChip(
                label: const Text('>= 20'),
                selected: _isPresetActive(20),
                onSelected: (selected) => _setMinScorePreset(20),
              ),
              ChoiceChip(
                label: const Text('>= 30'),
                selected: _isPresetActive(30),
                onSelected: (selected) => _setMinScorePreset(30),
              ),
              ChoiceChip(
                label: const Text('>= 40'),
                selected: _isPresetActive(40),
                onSelected: (selected) => _setMinScorePreset(40),
              ),
              ChoiceChip(
                label: const Text('Clear'),
                selected: _isPresetActive(0),
                onSelected: (selected) => _setMinScorePreset(0),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              const Text('Sort by:'),
              ChoiceChip(
                label: const Text('Score'),
                selected: _sortField == _ProductSortField.score,
                onSelected: (selected) => _setSortField(_ProductSortField.score),
              ),
              ChoiceChip(
                label: const Text('Price'),
                selected: _sortField == _ProductSortField.price,
                onSelected: (selected) => _setSortField(_ProductSortField.price),
              ),
              ChoiceChip(
                label: const Text('MOQ'),
                selected: _sortField == _ProductSortField.moq,
                onSelected: (selected) => _setSortField(_ProductSortField.moq),
              ),
              ChoiceChip(
                label: const Text('Lead Time'),
                selected: _sortField == _ProductSortField.leadTime,
                onSelected: (selected) => _setSortField(_ProductSortField.leadTime),
              ),
              InputChip(
                label: Text(_sortDirectionLabel),
                avatar: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                onPressed: _toggleSortDirection,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _filterSummaryText,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Product>>(
            future: _shortlistProducts,
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No products shortlisted yet.'),
                );
              }
              return DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Price')),
                  DataColumn(label: Text('MOQ')),
                  DataColumn(label: Text('Lead time')),
                  DataColumn(label: Text('Score')),
                  DataColumn(label: Text('Action')),
                ],
                rows: snap.data!.map((p) {
                  final score = _shortlistScore(p);
                  final bandColor = _shortlistScoreBandColor(score);
                  final band = _shortlistScoreBand(score);

                  return DataRow(cells: [
                    DataCell(Text(p.name)),
                    DataCell(Text(p.quotedPrice == null ? 'N/A' : '${p.quotedPrice} ${p.priceCurrency}')),
                    DataCell(Text(p.moq == null ? 'N/A' : p.moq.toString())),
                    DataCell(Text(p.leadTime.isEmpty ? 'N/A' : p.leadTime)),
                    DataCell(
                      Row(
                        children: [
                          Text(score.toStringAsFixed(2)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: bandColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Tier $band',
                              style: TextStyle(
                                color: bandColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove shortlist',
                        onPressed: () => _toggleProductShortlist(p),
                      ),
                    ),
                  ]);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
