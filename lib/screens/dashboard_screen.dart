import 'package:flutter/material.dart';
import '../data/product_score.dart';

import '../data/database.dart';
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
  late Future<List<_TodayAtFairItem>> _futureTodayAtFair;
  late Future<List<Sample>> _futureSampleAlerts;

  @override
  void initState() {
    super.initState();
    _reloadFutures();
  }

  void _reloadFutures() {
    _futureStats = db.getStats();
    _futureCloseouts = db.getTripCloseoutSummaries();
    _futureTopShortlist = _loadTopShortlist();
    _futureTodayAtFair = _loadTodayAtFair();
    _futureSampleAlerts = _loadSampleAlerts();
  }

  void _reload() => setState(_reloadFutures);

  Future<List<Product>> _loadTopShortlist() async {
    final products = await db.getShortlistedProducts();
    products.sort((a, b) => _shortlistScore(b).compareTo(_shortlistScore(a)));
    return products.take(20).toList();
  }

  Future<List<_TodayAtFairItem>> _loadTodayAtFair() async {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final suppliers = await db.getExhibitors(null);
    final meetings = await db.getMeetings();
    final items = <_TodayAtFairItem>[];
    final scheduledSupplierIds = <int>{};

    for (final supplier in suppliers) {
      final scheduled = supplier.plannedVisitAt?.toLocal();
      if (scheduled != null && DateUtils.isSameDay(scheduled, now)) {
        scheduledSupplierIds.add(supplier.id!);
        items.add(_TodayAtFairItem.visit(supplier, scheduled));
      }
    }

    for (final meeting in meetings) {
      final supplier =
          suppliers.where((item) => item.id == meeting.exhibitorId);
      final name =
          supplier.isEmpty ? 'Supplier follow-up' : supplier.first.name;
      final due = meeting.followUpDate?.toLocal();
      if (!meeting.completed && due != null && !due.isAfter(endOfToday)) {
        items.add(_TodayAtFairItem.followUp(meeting, name, due, now));
      } else if (DateUtils.isSameDay(meeting.meetingDate.toLocal(), now)) {
        items.add(_TodayAtFairItem.meeting(meeting, name));
      }
    }

    final prioritySuppliers = suppliers
        .where((supplier) =>
            supplier.visitedAt == null &&
            !scheduledSupplierIds.contains(supplier.id) &&
            (supplier.shortlisted || supplier.rating >= 4))
        .toList()
      ..sort((a, b) {
        final shortlist =
            (b.shortlisted ? 1 : 0).compareTo(a.shortlisted ? 1 : 0);
        return shortlist != 0 ? shortlist : b.rating.compareTo(a.rating);
      });
    items.addAll(prioritySuppliers.take(2).map(_TodayAtFairItem.priority));

    items.sort((a, b) {
      final left = a.when ?? DateTime(now.year, now.month, now.day, 23, 58);
      final right = b.when ?? DateTime(now.year, now.month, now.day, 23, 58);
      return left.compareTo(right);
    });
    return items;
  }

  Future<List<Sample>> _loadSampleAlerts() async {
    final now = DateTime.now();
    final terminal = {'Approved', 'Rejected'};
    final samples = await db.getSamples();
    return samples
        .where((sample) =>
            !terminal.contains(sample.status) &&
            (sample.expectedAt == null || !sample.expectedAt!.isAfter(now)))
        .toList()
      ..sort((left, right) {
        final leftDate = left.expectedAt ?? left.requestedAt;
        final rightDate = right.expectedAt ?? right.requestedAt;
        return leftDate.compareTo(rightDate);
      });
  }

  double _shortlistScore(Product p) => ProductScore.fromRating(p.rating);

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
            AppColors.primary,
            AppColors.teal,
          ];
          final icons = [
            Icons.public,
            Icons.business,
            Icons.inventory_2,
            Icons.star,
            Icons.alarm
          ];

          return EnterprisePage(
            title: 'Today at the fair',
            subtitle:
                'Your priorities, supplier conversations, and follow-ups in one place.',
            children: [
              SectionPanel(
                title: 'Record a conversation',
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
                            label: const Text('Scan card details'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _todayAtFairSection(),
              const SizedBox(height: 16),
              _sampleAlertsSection(),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Today: agenda and due tasks',
                subtitle:
                    'A quick view of today only. Open Follow-ups for the complete team queue.',
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
                      mainAxisExtent: 160 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 80).toDouble(),
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

  Widget _todayAtFairSection() {
    return SectionPanel(
      title: 'Today at the Fair',
      subtitle:
          'Visits, meetings, urgent follow-ups, and priority suppliers in one place.',
      trailing: TextButton(
        onPressed: widget.onCapture,
        child: const Text('Open visits'),
      ),
      child: FutureBuilder<List<_TodayAtFairItem>>(
        future: _futureTodayAtFair,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No visits or urgent follow-ups planned today.'),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: widget.onCapture,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Schedule a supplier visit'),
                ),
              ],
            );
          }
          return Column(
            children: [
              ...items.take(7).map((item) => _TodayAtFairTile(
                    item: item,
                    onTap: item.kind == _TodayItemKind.followUp
                        ? widget.onFollowUps
                        : widget.onCapture,
                  )),
              if (items.length > 7)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onCapture,
                    child: Text('View ${items.length - 7} more in visits'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sampleAlertsSection() => SectionPanel(
        title: 'Sample watch',
        subtitle: 'Samples that need receipt or testing attention.',
        child: FutureBuilder<List<Sample>>(
          future: _futureSampleAlerts,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final samples = snapshot.data!;
            if (samples.isEmpty) {
              return const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: AppColors.teal),
                  SizedBox(width: 10),
                  Expanded(child: Text('No samples currently need attention.')),
                ],
              );
            }
            return Column(
              children: samples.take(3).map((sample) {
                final late = sample.expectedAt != null &&
                    sample.expectedAt!.isBefore(DateTime.now());
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      late
                          ? Icons.warning_amber_outlined
                          : Icons.inventory_2_outlined,
                      color: late ? AppColors.danger : AppColors.amber),
                  title: Text(sample.status),
                  subtitle: Text(
                      '${sample.expectedAt == null ? 'Expected arrival not set' : 'Expected ${sample.expectedAt!.toLocal().toString().substring(0, 10)}'}${sample.trackingNumber.isEmpty ? '' : ' | ${sample.trackingNumber}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onCapture,
                );
              }).toList(),
            );
          },
        ),
      );
}

enum _TodayItemKind { visit, meeting, followUp, priority }

class _TodayAtFairItem {
  final _TodayItemKind kind;
  final String title;
  final String detail;
  final DateTime? when;
  final bool overdue;
  final String? priority;

  const _TodayAtFairItem({
    required this.kind,
    required this.title,
    required this.detail,
    this.when,
    this.overdue = false,
    this.priority,
  });

  factory _TodayAtFairItem.visit(Exhibitor supplier, DateTime scheduled) =>
      _TodayAtFairItem(
        kind: _TodayItemKind.visit,
        title: supplier.name,
        detail:
            'Booth ${supplier.booth.isEmpty ? '-' : supplier.booth}${supplier.hall.isEmpty ? '' : ' | ${supplier.hall}'}',
        when: scheduled,
      );

  factory _TodayAtFairItem.meeting(Meeting meeting, String supplierName) =>
      _TodayAtFairItem(
        kind: _TodayItemKind.meeting,
        title: supplierName,
        detail: meeting.outcome.isEmpty ? 'Supplier meeting' : meeting.outcome,
        when: meeting.meetingDate.toLocal(),
        priority: meeting.priority,
      );

  factory _TodayAtFairItem.followUp(
          Meeting meeting, String supplierName, DateTime due, DateTime now) =>
      _TodayAtFairItem(
        kind: _TodayItemKind.followUp,
        title: supplierName,
        detail: meeting.assigneeEmail.isEmpty
            ? '${meeting.priority} priority follow-up'
            : '${meeting.priority} priority | ${meeting.assigneeEmail}',
        when: due,
        overdue: due.isBefore(now),
        priority: meeting.priority,
      );

  factory _TodayAtFairItem.priority(Exhibitor supplier) => _TodayAtFairItem(
        kind: _TodayItemKind.priority,
        title: supplier.name,
        detail:
            '${supplier.shortlisted ? 'Shortlisted' : 'Rated ${supplier.rating}/5'}${supplier.booth.isEmpty ? '' : ' | Booth ${supplier.booth}'}',
        priority: 'Priority',
      );
}

class _TodayAtFairTile extends StatelessWidget {
  final _TodayAtFairItem item;
  final VoidCallback? onTap;

  const _TodayAtFairTile({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (item.kind) {
      _TodayItemKind.visit => (
          Icons.location_on_outlined,
          AppColors.primary,
          'Visit'
        ),
      _TodayItemKind.meeting => (
          Icons.groups_2_outlined,
          const Color(0xFF6B4E9B),
          'Meeting'
        ),
      _TodayItemKind.followUp => (
          item.overdue ? Icons.warning_amber_outlined : Icons.task_alt,
          item.overdue ? AppColors.danger : AppColors.amber,
          item.overdue ? 'Overdue' : 'Follow-up',
        ),
      _TodayItemKind.priority => (
          Icons.star_outline,
          AppColors.teal,
          'Priority'
        ),
    };
    final time = item.when == null
        ? 'Next'
        : '${item.when!.hour.toString().padLeft(2, '0')}:${item.when!.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: SizedBox(
        width: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(icon, color: color),
    );
  }
}
