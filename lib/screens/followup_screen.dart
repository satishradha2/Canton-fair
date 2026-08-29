import 'package:flutter/material.dart';
import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';

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
          final due = data.where((m) => m.followUpDate != null && !m.completed).toList()
            ..sort((a, b) => (a.followUpDate ?? now).compareTo(b.followUpDate ?? now));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: due.length,
            itemBuilder: (_, i) {
              final m = due[i];
              final fu = m.followUpDate!;
              final overdue = _isOverdue(fu);
              final rowColor = overdue ? Colors.red.shade50 : Colors.green.shade50;
              return Card(
                color: rowColor,
                child: ListTile(
                  title: Text('Supplier #${m.exhibitorId}'),
                  subtitle: Text(
                    'Follow-up: ${fu.toLocal()} | Outcome: ${m.outcome} | Priority: ${m.priority}\n${m.notes}',
                  ),
                  leading: Icon(overdue ? Icons.warning : Icons.schedule),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    tooltip: 'Mark done',
                    onPressed: () => _completeMeeting(m),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
