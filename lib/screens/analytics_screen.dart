import 'package:flutter/material.dart';
import '../data/database.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _analytics;

  @override
  void initState() {
    super.initState();
    _analytics = _build();
  }

  Future<List<Map<String, dynamic>>> _build() async {
    final all = await db.getStats();
    final allRows = await db.queryAll('exhibitors', orderBy: 'rating DESC');
    final grouped = <String, int>{};
    for (final row in allRows) {
      final cat = (row['category'] as String?)?.trim();
      if (cat == null || cat.isEmpty) continue;
      grouped[cat] = (grouped[cat] ?? 0) + 1;
    }
    final topCategoryRows = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topList = topCategoryRows.take(5).map((e) => {'label': e.key, 'value': e.value}).toList();

    return [...all, ...topList];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _analytics,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final base = data.take(5).toList();
        final cats = data.skip(5).toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Business Intelligence', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Core metrics'),
            const SizedBox(height: 8),
            ...base.map((e) => Card(
                  child: ListTile(
                    title: Text(e['label'].toString()),
                    trailing: Text(
                      e['value'].toString(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                )),
            const SizedBox(height: 12),
            const Text('Top categories by entries'),
            const SizedBox(height: 8),
            if (cats.isEmpty)
              const Text('Add categories to products for insights.')
            else
              ...cats.map((e) => ListTile(title: Text(e['label'].toString()), trailing: Text(e['value'].toString()))),
            const SizedBox(height: 14),
            const Card(
              child: ListTile(
                title: Text('Future analytics'),
                subtitle: Text(
                  'Planned: quote comparison charts, visit efficiency, supplier trust score, and day-wise KPI summary.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

