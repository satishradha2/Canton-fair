import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'approval_policy.dart';
import 'database.dart';
import 'team_workspace_service.dart';
import 'shortlist_service.dart';

class ProductCaptureService {
  static Future<bool> canWrite() async {
    final scope = await TeamWorkspaceService().scopeKey();
    const storage = FlutterSecureStorage();
    try {
      final role = await ApprovalPolicy.currentRole().timeout(const Duration(seconds: 8));
      await storage.write(key: 'product_capture_role_$scope', value: role);
      return ['admin', 'member'].contains(role);
    } catch (error) {
      if (error is SocketException || error is TimeoutException || error is http.ClientException) {
        return ['admin', 'member'].contains(await storage.read(key: 'product_capture_role_$scope'));
      }
      rethrow;
    }
  }

  static List<dynamic> quotationHistory(List<dynamic> history, Map<String, dynamic> quotation,
      String recordedAt, String recordedBy) {
    final next = List<dynamic>.from(history);
    final last = next.isEmpty ? null : Map<String, dynamic>.from(next.last as Map);
    last?.remove('recorded_at');
    last?.remove('recorded_by');
    final unchanged = last != null && quotation.entries.every((entry) => last[entry.key] == entry.value);
    if (quotation['price'] != null && !unchanged) {
      next.add({...quotation, 'recorded_at': recordedAt, 'recorded_by': recordedBy});
    }
    return next;
  }
  static Future<void> checkScope(String scope) async {
    if (scope != await TeamWorkspaceService().scopeKey()) {
      throw StateError('Workspace changed. Reopen the company.');
    }
  }

  static Future<Directory> _folder(String scope, int supplier) async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(paths.join(root.path, 'product_capture', scope, '$supplier'));
    await folder.create(recursive: true);
    return folder;
  }

  static Future<File> _draft(String scope, int supplier, int? product) async =>
      File(paths.join((await _folder(scope, supplier)).path, 'draft_${product ?? 'new'}.json'));

  static Future<Map<String, dynamic>?> loadDraft(String scope, int supplier, int? product) async {
    await checkScope(scope);
    final file = await _draft(scope, supplier, product);
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
  }

  static Future<void> writeDraft(String scope, int supplier, int? product, Map<String, dynamic> data) async {
    await checkScope(scope);
    final file = await _draft(scope, supplier, product);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }

  static Future<void> clearDraft(String scope, int supplier, int? product) async {
    await checkScope(scope);
    final file = await _draft(scope, supplier, product);
    if (await file.exists()) await file.delete();
  }

  static Future<String> keepPhoto(String scope, int supplier, String source) async {
    await checkScope(scope);
    final file = File(source);
    final hash = sha256.convert(await file.readAsBytes()).toString();
    final extension = paths.extension(source).toLowerCase();
    final stored = File(paths.join((await _folder(scope, supplier)).path, '$hash${RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '.jpg'}'));
    if (!await stored.exists()) await file.copy(stored.path);
    return stored.path;
  }

  static Future<Map<String, dynamic>> loadProduct(int id) async {
    final db = await TradeDatabase.instance.database;
    final rows = await db.rawQuery('''SELECT p.*, c.name AS category
      FROM products p LEFT JOIN product_category_assignments a ON a.product_id=p.id
      LEFT JOIN product_categories c ON c.id=a.category_id WHERE p.id=?''', [id]);
    if (rows.isEmpty) throw StateError('Product is no longer available.');
    final row = rows.first;
    final details = ApprovalPolicy.jsonObject(row['details_json']);
    int? fairId = details['fair_id'] as int?;
    if (details['fair_name'] is String) {
      final matching = await db.query('trips', where: 'name=?', whereArgs: [details['fair_name']]);
      fairId = matching.length == 1 ? matching.first['id'] as int : null;
    }
    final photos = await TradeDatabase.instance.getAttachments('product', id);
    final fields = <String, String>{
      for (final entry in details.entries) if (entry.value is String) entry.key: entry.value as String,
      for (final key in ['name', 'model_code', 'specs', 'moq', 'quoted_price', 'price_currency', 'lead_time', 'payment_terms', 'category']) key: row[key]?.toString() ?? '',
    };
    return {
      'fields': fields, 'fair_id': fairId,
      'shortlisted': row['shortlisted'] == 1,
      'shortlist_reason': ApprovalPolicy.jsonObject(details['shortlist'])['reason'] ?? '',
      'specifications': details['specifications'] ?? [],
      'ai_pending': details['ai_pending'] ?? false,
      'ai_cache': details['ai_cache'],
      'quote_history': details['quote_history'] ?? [],
      'additional_categories': details['additional_categories'] ?? [],
      'photos': [for (final photo in photos.where((item) => item.kind == 'image')) {
        'path': photo.path,
        'role': _photoMeta(photo)['role'] ?? 'Product view',
        'cover': _photoMeta(photo)['cover'] ?? false,
        'source_key': _photoMeta(photo)['source_key'],
      }],
    };
  }

  static Map<String, dynamic> _photoMeta(Attachment photo) {
    try { return ApprovalPolicy.jsonObject(photo.note); } catch (_) { return {}; }
  }

  static Future<int> save({required String scope, required int supplier,
    int? product, required Map<String, dynamic> draft}) => TeamWorkspaceService.exclusive(() async {
    await checkScope(scope);
    if (!await canWrite()) throw StateError('A member or administrator role is required.');
    final fields = Map<String, dynamic>.from(draft['fields'] as Map);
    String value(String key) => (fields[key] ?? '').toString().trim();
    if (value('name').isEmpty || value('category').isEmpty) throw StateError('Product name and a master category are required.');
    final currency = value('price_currency').toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) throw StateError('Use a three-letter currency code.');
    double? number(String key) {
      if (value(key).isEmpty) return null;
      final result = double.tryParse(value(key));
      if (result == null || !result.isFinite || result < 0) throw StateError('Enter a valid $key.');
      return result;
    }
    final price = number('quoted_price');
    final moq = number('moq');
    final photos = (draft['photos'] as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    for (final photo in photos) {
      if (!await File(photo['path'] as String).exists()) throw StateError('A photo is unavailable. Please replace it.');
    }
    final db = await TradeDatabase.instance.database;
    return db.transaction((txn) async {
      if ((await txn.query('exhibitors', where: 'id=?', whereArgs: [supplier])).isEmpty) throw StateError('Company was removed.');
      final categories = await txn.query('product_categories', where: 'name=? AND archived=0', whereArgs: [value('category')]);
      if (categories.isEmpty) throw StateError('Select an active category from Masters.');
      final additionalCategories = List<String>.from(draft['additional_categories'] as List? ?? []);
      final allCategories = await txn.query('product_categories', where: 'archived=0');
      final activeNames = allCategories.map((row) => row['name']).toSet();
      if (!activeNames.containsAll(additionalCategories)) throw StateError('Choose additional categories from the active master list.');
      final fairId = draft['fair_id'];
      final fairRows = fairId == null ? <Map<String, Object?>>[] : await txn.query('trips', where: 'id=?', whereArgs: [fairId]);
      if (fairRows.isEmpty) throw StateError('Choose the fair for this capture.');
      final fairName = fairRows.first['name'] as String;
      final duplicate = await txn.rawQuery('''SELECT id FROM products WHERE exhibitor_id=?
        AND lower(trim(name))=? AND lower(trim(model_code))=? AND id<>?''',
        [supplier, value('name').toLowerCase(), value('model_code').toLowerCase(), product ?? -1]);
      if (duplicate.isNotEmpty) throw StateError('This product/model already exists under the company. Open it to add details.');
      Map<String, dynamic> previous = {};
      bool wasShortlisted = false;
      if (product != null) {
        final rows = await txn.query('products', where: 'id=? AND exhibitor_id=?', whereArgs: [product, supplier]);
        if (rows.isEmpty) throw StateError('Product was removed.');
        previous = ApprovalPolicy.jsonObject(rows.first['details_json']);
        wasShortlisted = rows.first['shortlisted'] == 1;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final user = Supabase.instance.client.auth.currentUser?.email ?? '';
      final quotation = {'price': price, 'currency': currency, 'moq': moq,
        'quantity_unit': value('quantity_unit'), 'price_basis': value('price_basis'),
        'price_breaks': value('price_breaks'), 'lead_time': value('lead_time'),
        'payment_terms': value('payment_terms'), 'fair_id': fairId, 'fair_name': fairName};
      final history = quotationHistory(previous['quote_history'] as List? ?? [], quotation, now, user);
      final details = {...previous, ...fields,
        'fair_id': fairId, 'fair_name': fairName, 'captured_at': previous['captured_at'] ?? now,
        'captured_by': previous['captured_by'] ?? user, 'updated_at': now,
        'specifications': draft['specifications'], 'quote_history': history,
        'ai_pending': draft['ai_pending'], 'ai_cache': draft['ai_cache'],
        'additional_categories': additionalCategories,
        'visit_keys': {...List<String>.from(previous['visit_keys'] as List? ?? []),
          if (draft['visit_key'] is String && (draft['visit_key'] as String).isNotEmpty) draft['visit_key'] as String}.toList(),
        'shortlist': ShortlistService.metadata(previous['shortlist'], selected: draft['shortlisted'] == true,
          wasSelected: wasShortlisted, reason: (draft['shortlist_reason'] ?? '').toString(), fair: fairName),
      };
      if (draft['shortlisted'] == true && draft['also_shortlist_supplier'] == true) {
        final companies = await txn.query('exhibitors', where: 'id=?', whereArgs: [supplier]);
        final company = companies.first;
        final capture = ApprovalPolicy.jsonObject(company['field_capture_json']);
        final oldMeta = ApprovalPolicy.jsonObject(capture['shortlist']);
        capture['shortlist'] = ShortlistService.metadata(oldMeta, selected: true,
          wasSelected: company['shortlisted'] == 1, reason: oldMeta['reason']?.toString() ?? '', fair: fairName);
        await txn.update('exhibitors', {'shortlisted': 1, 'field_capture_json': jsonEncode(capture)}, where: 'id=?', whereArgs: [supplier]);
      }
      final values = {'exhibitor_id': supplier, 'name': value('name'), 'model_code': value('model_code'),
        'specs': value('specs'), 'moq': moq, 'quoted_price': price, 'price_currency': currency,
        'lead_time': value('lead_time'), 'payment_terms': value('payment_terms'),
        'shortlisted': draft['shortlisted'] == true ? 1 : 0, 'details_json': jsonEncode(details)};
      final id = product ?? await txn.insert('products', values);
      if (product != null) await txn.update('products', values, where: 'id=?', whereArgs: [id]);
      await txn.rawInsert('INSERT OR REPLACE INTO product_category_assignments(product_id,category_id) VALUES(?,?)', [id, categories.first['id']]);
      final oldPhotos = await txn.query('attachments', where: "owner_type='product' AND owner_id=? AND kind='image'", whereArgs: [id]);
      final folder = Directory(paths.join((await getApplicationDocumentsDirectory()).path, 'attachments', scope, 'product_$id'));
      await folder.create(recursive: true);
      final retained = <int>{};
      final copies = <String, String>{};
      final sourceKeys = <String, String>{};
      for (final photo in photos) {
        final sourcePath = photo['path'] as String;
        final sourceKey = sha256.convert(await File(sourcePath).readAsBytes()).toString();
        sourceKeys[sourcePath] = sourceKey;
        final matches = oldPhotos.where((row) {
          if (row['path'] == sourcePath) return true;
          try { return ApprovalPolicy.jsonObject(row['note'])['source_key'] == sourceKey; }
          catch (_) { return false; }
        }).toList();
        final note = jsonEncode({'role': photo['role'], 'cover': photo['cover'] == true, 'source_key': sourceKey});
        if (matches.isNotEmpty) {
          final attachmentId = matches.first['id'] as int;
          retained.add(attachmentId);
          copies[sourcePath] = matches.first['path'] as String;
          await txn.update('attachments', {'note': note}, where: 'id=?', whereArgs: [attachmentId]);
        } else {
          final hash = sha256.convert(await File(sourcePath).readAsBytes()).toString();
          final stored = paths.join(folder.path, '$hash${paths.extension(sourcePath)}');
          if (!await File(stored).exists()) await File(sourcePath).copy(stored);
          copies[sourcePath] = stored;
          retained.add(await txn.insert('attachments', {'owner_type': 'product', 'owner_id': id, 'kind': 'image', 'path': stored, 'note': note}));
        }
      }
      final specs = (draft['specifications'] as List).map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        if (sourceKeys.containsKey(row['source'])) row['source_key'] = sourceKeys[row['source']];
        if (copies.containsKey(row['source'])) row['source'] = copies[row['source']];
        return row;
      }).toList();
      details['specifications'] = specs;
      await txn.update('products', {'details_json': jsonEncode(details)}, where: 'id=?', whereArgs: [id]);
      for (final old in oldPhotos) {
        if (!retained.contains(old['id'])) await txn.delete('attachments', where: 'id=?', whereArgs: [old['id']]);
      }
      return id;
    });
  });
}
