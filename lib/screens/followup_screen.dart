import 'package:flutter/material.dart';
import '../data/database.dart';
import '../data/cloud_api_service.dart';
import '../data/language_service.dart';
import '../data/reminder_service.dart';
import '../data/team_workspace_service.dart';
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

  Future<void> _postpone(Meeting meeting) async {
    final date =
        (meeting.followUpDate ?? DateTime.now()).add(const Duration(days: 1));
    await db.update(
        'meetings', meeting.id!, {'follow_up_date': date.toIso8601String()});
    await ReminderService.scheduleFollowUp(
      id: meeting.id!,
      title: 'Supplier follow-up is due',
      body: 'Postponed follow-up: ${meeting.outcome}',
      at: date,
    );
    _refresh();
  }

  Future<List<CloudMember>> _loadCloudTeamMembers() async {
    final workspace = await TeamWorkspaceService().load();
    if (workspace == null) return const [];
    return CloudApiService().members(
      CloudTeam(id: workspace.id, name: workspace.name, role: 'member'),
    );
  }

  Future<void> _assign(Meeting meeting) async {
    List<CloudMember> members;
    try {
      members = await _loadCloudTeamMembers();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load cloud team members: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Invite a cloud team member before assigning tasks.')),
      );
      return;
    }
    var selectedEmail = meeting.assigneeEmail;
    final email = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign follow-up'),
          content: DropdownButtonFormField<String>(
            value: selectedEmail,
            decoration: const InputDecoration(labelText: 'Team member'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Unassigned')),
              ...members.map((member) => DropdownMenuItem(
                    value: member.email,
                    child: Text('${member.email} (${member.role})'),
                  )),
            ],
            onChanged: (value) =>
                setDialogState(() => selectedEmail = value ?? ''),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, selectedEmail),
                child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (email == null) return;
    await db.update('meetings', meeting.id!, {'assignee_email': email});
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
            title: tr(context, 'followUpQueue'),
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
                    child: Dismissible(
                      key: ValueKey('followup-${m.id}'),
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.startToEnd) {
                          await _completeMeeting(m);
                        } else {
                          await _postpone(m);
                        }
                        return false;
                      },
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                            color: AppColors.teal,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.check, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.snooze_outlined,
                            color: Colors.white),
                      ),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color:
                                  (overdue ? AppColors.danger : AppColors.teal)
                                      .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                                overdue ? Icons.warning : Icons.schedule,
                                color: overdue
                                    ? AppColors.danger
                                    : AppColors.teal),
                          ),
                          title: FutureBuilder<Exhibitor?>(
                            future: db.getExhibitorById(m.exhibitorId),
                            builder: (context, supplierSnapshot) => Text(
                              supplierSnapshot.data?.name ??
                                  'Supplier #${m.exhibitorId}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                FutureBuilder<Exhibitor?>(
                                  future: db.getExhibitorById(m.exhibitorId),
                                  builder: (context, supplierSnapshot) {
                                    final booth =
                                        supplierSnapshot.data?.booth ?? '';
                                    if (booth.isEmpty)
                                      return const SizedBox.shrink();
                                    return Text('Booth $booth');
                                  },
                                ),
                                if (m.notes.isNotEmpty)
                                  Text(m.notes,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                if (m.assigneeEmail.isNotEmpty)
                                  Text('Assigned: ${m.assigneeEmail}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          trailing: Wrap(children: [
                            IconButton(
                                icon: const Icon(Icons.person_add_alt_1),
                                tooltip: 'Assign',
                                onPressed: () => _assign(m)),
                            IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                tooltip: 'Mark done',
                                onPressed: () => _completeMeeting(m)),
                          ]),
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
