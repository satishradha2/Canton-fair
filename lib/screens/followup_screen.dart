import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  late Future<List<_FollowUpPackCandidate>> _packFuture;

  @override
  void initState() {
    super.initState();
    _dueFuture = db.getDueFollowUps();
    _packFuture = _loadFollowUpPack();
  }

  void _refresh() => setState(() {
        _dueFuture = db.getDueFollowUps();
        _packFuture = _loadFollowUpPack();
      });

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

  Future<List<_FollowUpPackCandidate>> _loadFollowUpPack() async {
    final candidates = <_FollowUpPackCandidate>[];
    for (final supplier in await db.getExhibitors(null)) {
      final contacts = await db.getContacts(supplier.id!);
      final products = await db.getProducts(supplier.id!);
      final missing = <String>[];
      if (contacts.isEmpty ||
          !contacts.any((contact) =>
              contact.email.isNotEmpty ||
              contact.whatsapp.isNotEmpty ||
              contact.phone.isNotEmpty)) {
        missing.add('contact details');
      }
      if (products.isEmpty) {
        missing.add('product details');
      } else {
        if (!products.any((product) => product.quotedPrice != null)) {
          missing.add('price');
        }
        if (!products.any((product) => product.moq != null)) missing.add('MOQ');
        if (!products.any((product) => product.leadTime.trim().isNotEmpty)) {
          missing.add('lead time');
        }
        if (!products
            .any((product) => product.paymentTerms.trim().isNotEmpty)) {
          missing.add('payment terms');
        }
      }
      if (!_hasCertificates(supplier.fieldCaptureJson)) {
        missing.add('certificates');
      }
      if (missing.isNotEmpty) {
        candidates.add(_FollowUpPackCandidate(
          supplier: supplier,
          contact: contacts.isEmpty ? null : contacts.first,
          missing: missing,
        ));
      }
    }
    candidates.sort((left, right) {
      final shortlist = (right.supplier.shortlisted ? 1 : 0)
          .compareTo(left.supplier.shortlisted ? 1 : 0);
      if (shortlist != 0) return shortlist;
      final missing = right.missing.length.compareTo(left.missing.length);
      return missing != 0
          ? missing
          : right.supplier.rating.compareTo(left.supplier.rating);
    });
    return candidates;
  }

  bool _hasCertificates(String fieldCaptureJson) {
    try {
      final data = jsonDecode(fieldCaptureJson) as Map<String, dynamic>;
      return (data['certifications'] as String? ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openFollowUpPackTask(_FollowUpPackCandidate candidate) async {
    List<CloudMember> members = const [];
    try {
      members = await _loadCloudTeamMembers();
    } catch (_) {}
    if (!mounted) return;
    var assigneeEmail = '';
    var dueAt = DateTime.now().add(const Duration(days: 1));
    var priority = candidate.supplier.shortlisted ? 'High' : 'Medium';
    var reminderEnabled = true;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create follow-up task'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(candidate.supplier.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Request: ${candidate.missing.join(', ')}'),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: assigneeEmail,
                  decoration: const InputDecoration(labelText: 'Assign to'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Unassigned')),
                    ...members.map((member) => DropdownMenuItem(
                          value: member.email,
                          child: Text('${member.email} (${member.role})'),
                        )),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => assigneeEmail = value ?? ''),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                      'Due: ${dueAt.year.toString().padLeft(4, '0')}-${dueAt.month.toString().padLeft(2, '0')}-${dueAt.day.toString().padLeft(2, '0')}'),
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: dueAt,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (selected != null) {
                      setDialogState(() => dueAt = DateTime(
                          selected.year, selected.month, selected.day, 9));
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'High', child: Text('High')),
                    DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'Low', child: Text('Low')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => priority = value ?? 'Medium'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: reminderEnabled,
                  title: const Text('Reminder at 9:00 AM'),
                  onChanged: (value) =>
                      setDialogState(() => reminderEnabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create task'),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    final meetingId = await db.insert(
      'meetings',
      Meeting(
        exhibitorId: candidate.supplier.id!,
        meetingDate: DateTime.now(),
        followUpDate: dueAt,
        outcome: 'Request missing supplier details',
        priority: priority,
        notes: candidate.message,
        assigneeEmail: assigneeEmail,
      ).toMap(),
    );
    if (reminderEnabled) {
      await ReminderService.scheduleFollowUp(
        id: meetingId,
        title: 'Supplier details follow-up is due',
        body: candidate.supplier.name,
        at: dueAt,
      );
    }
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Follow-up created for ${candidate.supplier.name}.')),
    );
  }

  Future<void> _sendFollowUpPack(
      _FollowUpPackCandidate candidate, String channel) async {
    final contact = candidate.contact;
    final uri = switch (channel) {
      'email' when contact != null && contact.email.isNotEmpty => Uri.parse(
          'mailto:${contact.email}?subject=${Uri.encodeComponent('Canton Fair follow-up')}&body=${Uri.encodeComponent(candidate.message)}'),
      'whatsapp'
          when contact != null &&
              (contact.whatsapp.isNotEmpty || contact.phone.isNotEmpty) =>
        Uri.https(
            'wa.me',
            '/${_digitsOnly(contact.whatsapp.isNotEmpty ? contact.whatsapp : contact.phone)}',
            {'text': candidate.message}),
      _ => throw StateError(
          'No ${channel == 'email' ? 'email' : 'WhatsApp or phone'} recorded'),
    };
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open $channel');
    }
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

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
            initialValue: selectedEmail,
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
              _followUpPackSection(),
              const SizedBox(height: 16),
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
                                      .withValues(alpha: 0.1),
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
                                    if (booth.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
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

  Widget _followUpPackSection() => SectionPanel(
        title: 'Canton Fair follow-up pack',
        subtitle: 'Request the supplier details that are still missing.',
        child: FutureBuilder<List<_FollowUpPackCandidate>>(
          future: _packFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final candidates = snapshot.data!;
            if (candidates.isEmpty) {
              return const Row(
                children: [
                  Icon(Icons.task_alt, color: AppColors.teal),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Captured suppliers have complete sourcing details.')),
                ],
              );
            }
            return Column(
              children: [
                ...candidates.take(5).map((candidate) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        candidate.supplier.shortlisted
                            ? Icons.star
                            : Icons.playlist_add_check,
                        color: candidate.supplier.shortlisted
                            ? AppColors.amber
                            : AppColors.primary,
                      ),
                      title: Text(candidate.supplier.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Missing: ${candidate.missing.join(', ')}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Follow-up actions',
                        onSelected: (value) async {
                          try {
                            if (value == 'task') {
                              await _openFollowUpPackTask(candidate);
                            } else {
                              await _sendFollowUpPack(candidate, value);
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                              value: 'task',
                              child: Text('Create assigned task')),
                          PopupMenuItem(
                              value: 'whatsapp',
                              child: Text('Send WhatsApp request')),
                          PopupMenuItem(
                              value: 'email',
                              child: Text('Send email request')),
                        ],
                      ),
                    )),
                if (candidates.length > 5)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        '${candidates.length - 5} more suppliers need follow-up.',
                        style: const TextStyle(color: AppColors.muted)),
                  ),
              ],
            );
          },
        ),
      );
}

class _FollowUpPackCandidate {
  final Exhibitor supplier;
  final Contact? contact;
  final List<String> missing;

  const _FollowUpPackCandidate({
    required this.supplier,
    required this.contact,
    required this.missing,
  });

  String get message {
    final recipient = contact?.name.trim().isNotEmpty == true
        ? contact!.name.trim()
        : 'there';
    return 'Hi $recipient, it was great meeting you at Canton Fair. '
        'Could you please share ${missing.join(', ')} for ${supplier.name}? '
        'Thank you.';
  }
}
