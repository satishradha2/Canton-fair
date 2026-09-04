import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  final _db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _activity;

  @override
  void initState() {
    super.initState();
    _activity = _db.getAuditLogs(limit: 100);
  }

  String _when(DateTime? value) {
    if (value == null) return '';
    final elapsed = DateTime.now().difference(value.toLocal());
    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => EnterprisePage(
        title: 'Team activity',
        subtitle: 'Recent supplier and team actions from the cloud workspace.',
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _activity = _db.getAuditLogs(limit: 100)),
          ),
        ],
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.66,
            child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _activity,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data!;
            if (records.isEmpty) {
              return Center(
                child: EmptyState(
                  icon: Icons.history_outlined,
                  title: 'No team activity yet',
                  message: 'Capture or update a supplier, then sync to share it with your team.',
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _activity = _db.getAuditLogs(limit: 100)),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final when = DateTime.tryParse(record['created_at'] as String? ?? '');
                  final actor = record['actor_email'] as String? ?? '';
                  final details = record['details'] as String? ?? '';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.teal.withValues(alpha: 0.12),
                        foregroundColor: AppColors.teal,
                        child: const Icon(Icons.person_outline),
                      ),
                      title: Text(record['action'] as String? ?? 'Activity'),
                      subtitle: Text([
                        if (details.isNotEmpty) details,
                        actor.isEmpty ? 'This device' : actor,
                      ].join('\n')),
                      isThreeLine: details.isNotEmpty,
                      trailing: Text(_when(when),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                    ),
                  );
                },
              ),
            );
          },
            ),
          ),
        ],
      );
}
