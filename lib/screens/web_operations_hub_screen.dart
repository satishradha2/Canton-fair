import 'package:flutter/material.dart';

import 'field_command_center_screen.dart';
import 'field_operations_screen.dart';
import 'field_visit_assistant_screen.dart';
import 'field_work_screen.dart';
import 'followup_screen.dart';
import 'hall_route_screen.dart';
import 'ocr_screen.dart';
import 'procurement_workspace_screen.dart';
import 'product_category_master_screen.dart';
import 'sync_status_screen.dart';

class WebOperationsHubScreen extends StatelessWidget {
  const WebOperationsHubScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Field tools')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= 720
                    ? 2
                    : 1;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Mobile tools, available on web',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Use the same operational records, roles, and sync status from a desktop browser.'),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 3.2 : 1.75,
                  children: [
                    _tool(context, Icons.dashboard_outlined, 'Field operations',
                        'Dashboard, product capture, visits, evidence, and field utilities.',
                        () => const FieldOperationsScreen()),
                    _tool(context, Icons.playlist_add_check_circle_outlined,
                        'Guided visit', 'Run a structured booth visit and close the follow-up.',
                        () => const FieldVisitAssistantScreen()),
                    _tool(context, Icons.route_outlined, 'Route planner',
                        'Create manual stops, organise halls, and review the map.',
                        () => const HallRouteScreen()),
                    _tool(context, Icons.category_outlined, 'Product categories',
                        'Create the shared category master used by product entry.',
                        () => const ProductCategoryMasterScreen()),
                    _tool(context, Icons.document_scanner_outlined, 'Card OCR review',
                        'Scan and correct business-card details before saving.',
                        () => const OcrScreen()),
                    _tool(context, Icons.sync_outlined, 'Offline sync center',
                        'Review queued changes, failures, and sync health.',
                        () => const SyncStatusScreen()),
                    _tool(context, Icons.event_note_outlined, 'Follow-up reminders',
                        'Review calls, samples, quotation deadlines, and assignments.',
                        () => const FollowUpScreen()),
                    _tool(context, Icons.handyman_outlined, 'Field work',
                        'Open operational checklists and active field records.',
                        () => const FieldWorkScreen()),
                    _tool(context, Icons.account_tree_outlined, 'Procurement workspace',
                        'Compare suppliers, quotations, and procurement decisions.',
                        () => const ProcurementWorkspaceScreen(initialTab: 2)),
                    _tool(context, Icons.hub_outlined, 'Command center',
                        'Use the field command center and its operational shortcuts.',
                        () => const FieldCommandCenterScreen()),
                  ],
                ),
              ],
            );
          },
        ),
      );

  Widget _tool(BuildContext context, IconData icon, String title, String detail,
      Widget Function() destination) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => destination()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
