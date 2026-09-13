import 'package:flutter/material.dart';

import '../data/cloud_health_service.dart';
import '../widgets/enterprise_widgets.dart';

class CloudHealthScreen extends StatefulWidget {
  const CloudHealthScreen({super.key});

  @override
  State<CloudHealthScreen> createState() => _CloudHealthScreenState();
}

class _CloudHealthScreenState extends State<CloudHealthScreen> {
  final _service = CloudHealthService();
  late Future<List<CloudHealthCheck>> _checks = _service.run();

  void _retry() => setState(() => _checks = _service.run());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Cloud readiness'),
          actions: [
            IconButton(
              tooltip: 'Run checks again',
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<CloudHealthCheck>>(
          future: _checks,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final checks = snapshot.data!;
            final ready = checks.every((check) => check.ok);
            return EnterprisePage(
              title: ready ? 'Cloud is ready' : 'Setup needs attention',
              subtitle: ready
                  ? 'Authentication, sync storage and server functions are responding.'
                  : 'Open each failed check for the exact deployment action.',
              children: [
                SectionPanel(
                  title:
                      '${checks.where((check) => check.ok).length} of ${checks.length} checks passed',
                  child: Column(
                    children: [
                      for (final check in checks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            check.ok
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: check.ok
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.error,
                          ),
                          title: Text(check.name),
                          subtitle: Text(check.detail),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}
