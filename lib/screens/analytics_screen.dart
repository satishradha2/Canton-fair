import 'package:flutter/material.dart';
import '../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

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
    final topList = topCategoryRows
        .take(5)
        .map((e) => {'label': e.key, 'value': e.value})
        .toList();

    return [...all, ...topList];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _analytics,
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final base = data.take(5).toList();
        final cats = data.skip(5).toList();
        return EnterprisePage(
          title: 'Business Intelligence',
          subtitle:
              'Supplier pipeline metrics and category concentration for trade-show decisions.',
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 700 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 4.4 : 3.4,
                  children: base.map((e) {
                    return MetricPill(
                      label: e['label'].toString(),
                      value: e['value'].toString(),
                      icon: Icons.analytics,
                      color: AppColors.primary,
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            SectionPanel(
              title: 'Top categories',
              subtitle:
                  'Most frequent supplier categories in your captured records.',
              child: cats.isEmpty
                  ? const EmptyState(
                      icon: Icons.category_outlined,
                      title: 'No category insight yet',
                      message:
                          'Add supplier categories to see concentration and buying focus.',
                    )
                  : Column(
                      children: cats.map((e) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(e['label'].toString(),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: InfoChip(
                              label: e['value'].toString(),
                              color: AppColors.teal),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}
