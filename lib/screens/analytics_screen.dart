import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/language_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsSnapshot {
  final int suppliers;
  final int products;
  final int shortlistedSuppliers;
  final int shortlistedProducts;
  final int plannedVisits;
  final int completedVisits;
  final int openFollowUps;
  final int overdueFollowUps;
  final int expiringQuotes;
  final int expiredQuotes;
  final int activeQuotes;
  final List<MapEntry<String, int>> visitDays;
  final List<Map<String, String>> riskSuppliers;

  const _AnalyticsSnapshot({
    required this.suppliers,
    required this.products,
    required this.shortlistedSuppliers,
    required this.shortlistedProducts,
    required this.plannedVisits,
    required this.completedVisits,
    required this.openFollowUps,
    required this.overdueFollowUps,
    required this.expiringQuotes,
    required this.expiredQuotes,
    required this.activeQuotes,
    required this.visitDays,
    required this.riskSuppliers,
  });
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final db = TradeDatabase.instance;
  late Future<_AnalyticsSnapshot> _analytics;

  @override
  void initState() {
    super.initState();
    _analytics = _build();
  }

  Future<_AnalyticsSnapshot> _build() async {
    final suppliers = await db.getExhibitors(null);
    final products =
        (await db.queryAll('products')).map(Product.fromMap).toList();
    final meetings = await db.getMeetings();
    final quotes = (await db.queryAll('quotes')).map(Quote.fromMap).toList();
    final now = DateTime.now();
    final expiryWindow = now.add(const Duration(days: 7));

    final visitsByDay = <String, int>{};
    for (final supplier in suppliers) {
      final visited = supplier.visitedAt?.toLocal();
      if (visited == null) continue;
      final key =
          '${visited.year.toString().padLeft(4, '0')}-${visited.month.toString().padLeft(2, '0')}-${visited.day.toString().padLeft(2, '0')}';
      visitsByDay[key] = (visitsByDay[key] ?? 0) + 1;
    }
    final visitDays = visitsByDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final productsBySupplier = <int, List<Product>>{};
    for (final product in products) {
      productsBySupplier
          .putIfAbsent(product.exhibitorId, () => [])
          .add(product);
    }
    final quoteProductIds = quotes.map((quote) => quote.productId).toSet();
    final overdueSupplierIds = meetings
        .where((meeting) =>
            !meeting.completed &&
            meeting.followUpDate != null &&
            meeting.followUpDate!.isBefore(now))
        .map((meeting) => meeting.exhibitorId)
        .toSet();
    final riskSuppliers = <Map<String, String>>[];
    for (final supplier in suppliers) {
      final risks = <String>[];
      final supplierProducts = productsBySupplier[supplier.id] ?? [];
      if (supplierProducts.isEmpty) {
        risks.add('No products');
      } else if (!supplierProducts
          .any((product) => quoteProductIds.contains(product.id))) {
        risks.add('No quote');
      }
      if (supplier.decisionScore > 0 && supplier.decisionScore < 40)
        risks.add('Low score');
      if (overdueSupplierIds.contains(supplier.id))
        risks.add('Follow-up overdue');
      if (risks.isNotEmpty)
        riskSuppliers.add({'name': supplier.name, 'risk': risks.join(' | ')});
    }

    return _AnalyticsSnapshot(
      suppliers: suppliers.length,
      products: products.length,
      shortlistedSuppliers:
          suppliers.where((supplier) => supplier.shortlisted).length,
      shortlistedProducts:
          products.where((product) => product.shortlisted).length,
      plannedVisits:
          suppliers.where((supplier) => supplier.plannedVisitAt != null).length,
      completedVisits:
          suppliers.where((supplier) => supplier.visitedAt != null).length,
      openFollowUps: meetings
          .where(
              (meeting) => !meeting.completed && meeting.followUpDate != null)
          .length,
      overdueFollowUps: overdueSupplierIds.length,
      expiringQuotes: quotes
          .where((quote) =>
              quote.validUntil != null &&
              !quote.validUntil!.isBefore(now) &&
              quote.validUntil!.isBefore(expiryWindow))
          .length,
      expiredQuotes: quotes
          .where((quote) =>
              quote.validUntil != null && quote.validUntil!.isBefore(now))
          .length,
      activeQuotes: quotes
          .where((quote) =>
              quote.validUntil == null || !quote.validUntil!.isBefore(now))
          .length,
      visitDays: visitDays.take(7).toList(),
      riskSuppliers: riskSuppliers.take(10).toList(),
    );
  }

  void _refresh() => setState(() => _analytics = _build());

  int _percent(int part, int total) =>
      total == 0 ? 0 : (part * 100 / total).round();

  Widget _metricGrid(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 700 ? 3 : 2;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 1.6 : 2.2,
            children: children,
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<_AnalyticsSnapshot>(
        future: _analytics,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          return EnterprisePage(
            title: tr(context, 'businessIntelligence'),
            subtitle:
                'Visit productivity, follow-up exposure, quote health, and supplier decision risk.',
            actions: [
              IconButton(
                  tooltip: 'Refresh analytics',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh),
            ],
            children: [
              _metricGrid([
                MetricPill(
                    label: 'Suppliers captured',
                    value: data.suppliers.toString(),
                    icon: Icons.business,
                    color: AppColors.primary),
                MetricPill(
                    label: 'Products captured',
                    value: data.products.toString(),
                    icon: Icons.inventory_2,
                    color: AppColors.teal),
                MetricPill(
                    label: 'Shortlist conversion',
                    value:
                        '${_percent(data.shortlistedSuppliers, data.suppliers)}%',
                    icon: Icons.workspace_premium,
                    color: AppColors.amber),
                MetricPill(
                    label: 'Visit completion',
                    value:
                        '${_percent(data.completedVisits, data.plannedVisits)}%',
                    icon: Icons.route,
                    color: AppColors.teal),
                MetricPill(
                    label: 'Overdue follow-ups',
                    value: data.overdueFollowUps.toString(),
                    icon: Icons.warning_amber,
                    color: AppColors.danger),
                MetricPill(
                    label: 'Quotes expiring',
                    value: data.expiringQuotes.toString(),
                    icon: Icons.hourglass_bottom,
                    color: AppColors.amber),
              ]),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Visit productivity',
                subtitle:
                    '${data.completedVisits} completed visits | ${data.plannedVisits} currently planned',
                child: data.visitDays.isEmpty
                    ? const EmptyState(
                        icon: Icons.route_outlined,
                        title: 'No visits completed yet',
                        message:
                            'Mark suppliers visited from Supplier Capture to measure daily activity.')
                    : Column(
                        children: data.visitDays
                            .map((entry) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.task_alt,
                                    color: AppColors.teal),
                                title: Text(entry.key),
                                trailing: InfoChip(
                                    label: '${entry.value} visits',
                                    color: AppColors.teal)))
                            .toList()),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Follow-up and quote health',
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  InfoChip(
                      label: '${data.openFollowUps} open follow-ups',
                      icon: Icons.event_available,
                      color: AppColors.primary),
                  InfoChip(
                      label: '${data.overdueFollowUps} overdue',
                      icon: Icons.error_outline,
                      color: AppColors.danger),
                  InfoChip(
                      label: '${data.activeQuotes} active quotes',
                      icon: Icons.request_quote,
                      color: AppColors.teal),
                  InfoChip(
                      label: '${data.expiringQuotes} expiring soon',
                      icon: Icons.timer_outlined,
                      color: AppColors.amber),
                  InfoChip(
                      label: '${data.expiredQuotes} expired',
                      icon: Icons.block,
                      color: AppColors.danger),
                  InfoChip(
                      label: '${data.shortlistedProducts} shortlisted products',
                      icon: Icons.star,
                      color: AppColors.primary),
                ]),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Supplier risk watchlist',
                subtitle:
                    'Suppliers needing a product, quote, score, or follow-up before a buying decision.',
                child: data.riskSuppliers.isEmpty
                    ? const EmptyState(
                        icon: Icons.verified_user_outlined,
                        title: 'No supplier risks detected',
                        message:
                            'Captured supplier records currently have no tracked risk flags.')
                    : Column(
                        children: data.riskSuppliers
                            .map((supplier) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.warning_amber,
                                    color: AppColors.danger),
                                title: Text(supplier['name']!),
                                subtitle: Text(supplier['risk']!)))
                            .toList()),
              ),
            ],
          );
        },
      ),
    );
  }
}
