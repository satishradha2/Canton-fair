import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/language_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onCapture;
  final VoidCallback? onScanQr;
  final VoidCallback? onScanCard;
  final VoidCallback? onSync;
  final VoidCallback? onFollowUps;

  const DashboardScreen({
    super.key,
    this.onCapture,
    this.onScanQr,
    this.onScanCard,
    this.onSync,
    this.onFollowUps,
  });

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
            actions: [
              ElevatedButton.icon(
                onPressed: widget.onCapture,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Capture supplier'),
              ),
            ],
            children: [
              SectionPanel(
                title: 'Quick capture',
                subtitle: 'Choose the fastest way to record a supplier.',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 390;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: compact ? double.infinity : 150,
                          child: ElevatedButton.icon(
                            onPressed: widget.onCapture,
                            icon: const Icon(Icons.add_business_outlined),
                            label: const Text('Add supplier'),
                          ),
                        ),
                        SizedBox(
                          width: compact ? double.infinity : 120,
                          child: OutlinedButton.icon(
                            onPressed: widget.onScanQr,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scan QR'),
                          ),
                        ),
                        SizedBox(
                          width: compact ? double.infinity : 130,
                          child: OutlinedButton.icon(
                            onPressed: widget.onScanCard,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Scan card'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Today',
                subtitle: 'Your overdue and due-today follow-ups.',
                trailing: TextButton(
                  onPressed: widget.onFollowUps,
                  child: const Text('View all'),
                ),
                child: FutureBuilder<List<Meeting>>(
                  future: db.getDueFollowUps(),
                  builder: (context, dueSnapshot) {
                    final now = DateTime.now();
                    final due = (dueSnapshot.data ?? const <Meeting>[])
                        .where((meeting) {
                      final date = meeting.followUpDate;
                      if (date == null || meeting.completed) return false;
                      return date.isBefore(now.add(const Duration(days: 1)));
                    }).toList()
                      ..sort(
                          (a, b) => a.followUpDate!.compareTo(b.followUpDate!));
                    if (dueSnapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    if (due.isEmpty) {
                      return Row(
                        children: [
                          const Icon(Icons.task_alt, color: AppColors.teal),
                          const SizedBox(width: 10),
                          const Expanded(
                              child: Text('No follow-ups due today.')),
                          TextButton.icon(
                              onPressed: widget.onSync,
                              icon: const Icon(Icons.sync),
                              label: const Text('Sync')),
                        ],
                      );
                    }
                    return Column(
                      children: due
                          .take(3)
                          .map((meeting) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                    meeting.followUpDate!.isBefore(now)
                                        ? Icons.warning_amber_outlined
                                        : Icons.schedule,
                                    color: meeting.followUpDate!.isBefore(now)
                                        ? AppColors.danger
                                        : AppColors.amber),
                                title: Text(
                                    meeting.assigneeEmail.isEmpty
                                        ? 'Unassigned follow-up'
                                        : meeting.assigneeEmail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${meeting.priority} priority | due ${meeting.followUpDate!.toLocal()}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: widget.onFollowUps,
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (stats.every((item) => (item['value'] as int? ?? 0) == 0)) ...[
                SectionPanel(
                  title: 'Get started',
                  subtitle:
                      'A short path to a useful shared sourcing workspace.',
                  child: Column(
                    children: [
                      const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.looks_one_outlined),
                        title: Text('Create your first trip'),
                        subtitle: Text(
                            'Organize suppliers by fair visit or sourcing trip.'),
                      ),
                      const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.looks_two_outlined),
                        title: Text('Capture a supplier'),
                        subtitle: Text(
                            'Record booth, contacts, products, and next steps.'),
                      ),
                      const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.looks_3_outlined),
                        title: Text('Invite a teammate and sync'),
                        subtitle: Text(
                            'Use Settings when you are ready to share the workspace.'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: widget.onCapture,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Capture first supplier'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
