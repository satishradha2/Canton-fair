import 'package:flutter/material.dart';
import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key});

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  final db = TradeDatabase.instance;
  late Future<List<Meeting>> _dueFuture;

  @override
  void initState() {
    super.initState();
    _dueFuture = db.getDueFollowUps();
  }

  void _refresh() => setState(() => _dueFuture = db.getDueFollowUps());

  bool _isOverdue(DateTime d) => d.isBefore(DateTime.now());

  Future<void> _completeMeeting(Meeting meeting) async {
    await db.update('meetings', meeting.id!, {'completed': 1});
    await ReminderService.cancel(meeting.id!);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Meeting>>(
        future: _dueFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final now = DateTime.now();
          final due = data
              .where((m) => m.followUpDate != null && !m.completed)
              .toList()
            ..sort((a, b) =>
                (a.followUpDate ?? now).compareTo(b.followUpDate ?? now));
          return EnterprisePage(
            title: 'Follow-up Queue',
            subtitle:
                'Prioritized supplier follow-ups and reminders that still need action.',
            children: [
              if (due.isEmpty)
                const EmptyState(
                  icon: Icons.task_alt,
                  title: 'No open follow-ups',
                  message:
                      'Scheduled supplier reminders will appear here when they are due.',
                )
              else
                ...due.map((m) {
                  final fu = m.followUpDate!;
                  final overdue = _isOverdue(fu);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (overdue ? AppColors.danger : AppColors.teal)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(overdue ? Icons.warning : Icons.schedule,
                              color:
                                  overdue ? AppColors.danger : AppColors.teal),
                        ),
                        title: Text('Supplier #${m.exhibitorId}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  InfoChip(
                                      label: overdue ? 'Overdue' : 'Due',
                                      color: overdue
                                          ? AppColors.danger
                                          : AppColors.teal),
                                  InfoChip(
                                      label: m.priority,
                                      icon: Icons.flag,
                                      color: AppColors.amber),
                                  InfoChip(
                                      label: m.outcome,
                                      icon: Icons.forum,
                                      color: AppColors.primary),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(fu.toLocal().toString(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (m.notes.isNotEmpty)
                                Text(m.notes,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          tooltip: 'Mark done',
                          onPressed: () => _completeMeeting(m),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
