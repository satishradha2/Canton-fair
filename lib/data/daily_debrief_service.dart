import '../models/models.dart';
import 'dart:convert';
import 'database.dart';

class DailyDebrief {
  final DateTime date;
  final int suppliersCaptured;
  final int suppliersVisited;
  final int shortlisted;
  final int productsCaptured;
  final int meetingsHeld;
  final int sampleRequests;
  final int openFollowUps;
  final int overdueFollowUps;
  final List<Exhibitor> priorityUnvisited;
  final List<Exhibitor> missedBooths;
  final Map<String, int> teamActivity;

  const DailyDebrief({
    required this.date,
    required this.suppliersCaptured,
    required this.suppliersVisited,
    required this.shortlisted,
    required this.productsCaptured,
    required this.meetingsHeld,
    required this.sampleRequests,
    required this.openFollowUps,
    required this.overdueFollowUps,
    required this.priorityUnvisited,
    required this.missedBooths,
    required this.teamActivity,
  });

  String get dateLabel =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String toShareText() {
    final lines = [
      'Canton Fair Daily Debrief - $dateLabel',
      '',
      'Captured: $suppliersCaptured suppliers, $productsCaptured products',
      'Field activity: $suppliersVisited visits, $meetingsHeld meetings, $sampleRequests sample requests',
      'Buying pipeline: $shortlisted shortlisted, $openFollowUps open follow-ups, $overdueFollowUps overdue',
      '',
      if (priorityUnvisited.isNotEmpty) 'Priority suppliers not yet visited:',
      ...priorityUnvisited.map((supplier) =>
          '- ${supplier.name}${supplier.booth.isEmpty ? '' : ' | Booth ${supplier.booth}'}'),
      if (missedBooths.isNotEmpty) ...[
        '',
        'Missed booths:',
        ...missedBooths.map((supplier) =>
            '- ${supplier.name}${supplier.booth.isEmpty ? '' : ' | Booth ${supplier.booth}'}'),
      ],
      if (teamActivity.isNotEmpty) ...[
        '',
        'Team activity:',
        ...teamActivity.entries
            .map((entry) => '- ${entry.key}: ${entry.value} meetings'),
      ],
    ];
    return lines.join('\n');
  }
}

class DailyDebriefService {
  final TradeDatabase _db;

  DailyDebriefService([TradeDatabase? database])
      : _db = database ?? TradeDatabase.instance;

  Future<DailyDebrief> build(DateTime selectedDate) async {
    final day =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final suppliers = await _db.getExhibitors(null);
    final products = await _db.queryAll('products');
    final meetings = await _db.getMeetings();
    final now = DateTime.now();

    final captured = (await _db.queryAll('exhibitors'))
        .where((row) => _isOnDay(_parseDate(row['created_at']), day))
        .length;
    final productsCaptured = products
        .where((row) => _isOnDay(_parseDate(row['created_at']), day))
        .length;
    final visited = suppliers
        .where((supplier) => _isOnDay(supplier.visitedAt?.toLocal(), day))
        .toList();
    final meetingsHeld = meetings
        .where((meeting) => _isOnDay(meeting.meetingDate.toLocal(), day))
        .toList();
    final sampleRequests = meetingsHeld
        .where((meeting) => '${meeting.outcome} ${meeting.notes}'
            .toLowerCase()
            .contains('sample'))
        .length;
    final openFollowUps = meetings
        .where((meeting) => !meeting.completed && meeting.followUpDate != null)
        .length;
    final overdueFollowUps = meetings
        .where((meeting) =>
            !meeting.completed &&
            meeting.followUpDate != null &&
            meeting.followUpDate!.isBefore(now))
        .length;
    final priorityUnvisited = suppliers
        .where((supplier) =>
            supplier.visitedAt == null &&
            (supplier.shortlisted || supplier.rating >= 4))
        .toList()
      ..sort((left, right) {
        final shortlist =
            (right.shortlisted ? 1 : 0).compareTo(left.shortlisted ? 1 : 0);
        return shortlist != 0 ? shortlist : right.rating.compareTo(left.rating);
      });
    final teamActivity = <String, int>{};
    for (final meeting in meetingsHeld) {
      final assignee =
          meeting.assigneeEmail.isEmpty ? 'Unassigned' : meeting.assigneeEmail;
      teamActivity[assignee] = (teamActivity[assignee] ?? 0) + 1;
    }
    final missedBooths = suppliers.where((supplier) {
      try {
        final data = jsonDecode(supplier.fieldCaptureJson);
        return data is Map && data['route_status'] == 'Missed';
      } catch (_) {
        return false;
      }
    }).toList();

    return DailyDebrief(
      date: day,
      suppliersCaptured: captured,
      suppliersVisited: visited.length,
      shortlisted: suppliers.where((supplier) => supplier.shortlisted).length,
      productsCaptured: productsCaptured,
      meetingsHeld: meetingsHeld.length,
      sampleRequests: sampleRequests,
      openFollowUps: openFollowUps,
      overdueFollowUps: overdueFollowUps,
      priorityUnvisited: priorityUnvisited.take(5).toList(),
      missedBooths: missedBooths.take(5).toList(),
      teamActivity: teamActivity,
    );
  }

  bool _isOnDay(DateTime? value, DateTime day) =>
      value != null &&
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
}
