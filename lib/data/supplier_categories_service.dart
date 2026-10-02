import 'dart:convert';

import '../models/models.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class SupplierCategoriesService {
  static Set<String> selected(Exhibitor company) {
    final metadata = ApprovalPolicy.jsonObject(company.fieldCaptureJson);
    final values = metadata['categories'];
    if (values is List) {
      return values.whereType<String>().where((name) => name.trim().isNotEmpty).toSet();
    }
    return company.category.split(',').map((name) => name.trim())
        .where((name) => name.isNotEmpty).toSet();
  }

  static Future<void> save(String scope, int companyId, Set<String> selected) =>
      TeamWorkspaceService.exclusive(() async {
        await ApprovalPolicy.requireWriter();
        if (await TeamWorkspaceService().scopeKey() != scope) {
          throw StateError('Workspace changed. Reopen the company.');
        }
        if (selected.isEmpty) throw StateError('Select at least one category.');
        final database = TradeDatabase.instance;
        final company = await database.getExhibitorById(companyId);
        if (company == null) throw StateError('This company is no longer available.');
        final db = await database.database;
        final masters = await db.query('product_categories', where: 'archived=0');
        final available = masters.map((row) => row['name'] as String).toSet();
        // Preserve existing assignments if a master has subsequently been archived.
        available.addAll(SupplierCategoriesService.selected(company));
        if (!available.containsAll(selected)) {
          throw StateError('A selected category is no longer available. Reopen the company and choose again.');
        }
        final names = selected.toList()..sort();
        final metadata = ApprovalPolicy.jsonObject(company.fieldCaptureJson);
        metadata['categories'] = names;
        await database.update('exhibitors', companyId, {
          'category': names.join(', '),
          'field_capture_json': jsonEncode(metadata),
        });
      });
}
