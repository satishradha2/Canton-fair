import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/language_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _futureStats;
  late Future<List<Map<String, dynamic>>> _futureCloseouts;
  late Future<List<Product>> _futureTopShortlist;

  @override
  void initState() {
    super.initState();
    _reloadFutures();
  }

  void _reloadFutures() {
    _futureStats = db.getStats();
    _futureCloseouts = db.getTripCloseoutSummaries();
    _futureTopShortlist = _loadTopShortlist();
  }

  void _reload() => setState(_reloadFutures);

  Future<List<Product>> _loadTopShortlist() async {
    final products = await db.getShortlistedProducts();
    products.sort((a, b) => _shortlistScore(b).compareTo(_shortlistScore(a)));
    return products.take(20).toList();
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureStats,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          final colors = [
            AppColors.primary,
            AppColors.teal,
            AppColors.amber,
            const Color(0xFF6B4E9B),
            const Color(0xFF2F855A),
          ];
          final icons = [
            Icons.public,
            Icons.business,
            Icons.inventory_2,
            Icons.star,
            Icons.alarm
          ];

          return EnterprisePage(
            title: tr(context, 'operations'),
            subtitle:
                'Live workspace for supplier capture, shortlisting, meetings, and trip closeout.',
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 900
                      ? 4
                      : width >= 620
                          ? 3
                          : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stats.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: width < 420 ? 1.18 : 1.45,
                    ),
                    itemBuilder: (context, i) {
                      return StatCard(
                        label: stats[i]['label'].toString(),
                        value: stats[i]['value'] as int,
                        icon: icons[i % icons.length],
                        color: colors[i % colors.length],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Trip closeout status',
                subtitle:
                    'Operational readiness by trip, including capture and shortlist coverage.',
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _futureCloseouts,
                  builder: (context, closeSnap) {
                    if (!closeSnap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (closeSnap.data!.isEmpty) {
                      return const EmptyState(
                        icon: Icons.event_busy,
                        title: 'No trip data yet',
                        message:
                            'Create a trip and start capturing suppliers to populate this dashboard.',
                      );
                    }
                    return Column(
                      children: closeSnap.data!.map((trip) {
                        final isClosed =
                            (trip['closed_at'] as String).isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFBFD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        trip['trip_name']?.toString() ?? 'Trip',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    InfoChip(
                                      label: isClosed ? 'Closed' : 'Open',
                                      icon: isClosed
                                          ? Icons.check_circle
                                          : Icons.schedule,
                                      color: isClosed
                                          ? AppColors.teal
                                          : AppColors.amber,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    InfoChip(
                                        label:
                                            '${trip['exhibitor_count']} suppliers',
                                        icon: Icons.business),
                                    InfoChip(
                                        label:
                                            '${trip['product_count']} products',
                                        icon: Icons.inventory_2,
                                        color: AppColors.teal),
                                    InfoChip(
                                        label:
                                            '${trip['contact_count']} contacts',
                                        icon: Icons.contacts,
                                        color: const Color(0xFF6B4E9B)),
                                    InfoChip(
                                        label:
                                            '${trip['meeting_count']} meetings',
                                        icon: Icons.event,
                                        color: AppColors.amber),
                                    InfoChip(
                                      label:
                                          '${trip['shortlisted_exhibitor_count']} / ${trip['shortlisted_product_count']} shortlisted',
                                      icon: Icons.star,
                                      color: const Color(0xFF2F855A),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Top shortlisted products',
                subtitle:
                    'Recommendation score blends rating, quote, MOQ, and lead time.',
                child: FutureBuilder<List<Product>>(
                  future: _futureTopShortlist,
                  builder: (context, scoreSnap) {
                    if (!scoreSnap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (scoreSnap.data!.isEmpty) {
                      return const EmptyState(
                        icon: Icons.star_border,
                        title: 'No shortlisted products',
                        message:
                            'Shortlist promising products to see your ranked buying options here.',
                      );
                    }
                    return Column(
                      children: scoreSnap.data!.map((p) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${p.quotedPrice == null ? "No price" : "${p.quotedPrice} ${p.priceCurrency}"}  |  MOQ ${p.moq ?? "-"}  |  ${p.leadTime.isEmpty ? "No lead time" : p.leadTime}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: InfoChip(
                            label: _shortlistScore(p).toStringAsFixed(1),
                            icon: Icons.trending_up,
                            color: AppColors.primary,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
