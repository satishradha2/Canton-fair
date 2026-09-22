import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/camera_capture_service.dart';
import '../data/database.dart';
import '../data/field_intelligence_service.dart';
import '../data/sync_status_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import 'scanner_screen.dart';

class IntelligenceLogisticsScreen extends StatefulWidget {
  const IntelligenceLogisticsScreen({super.key});

  @override
  State<IntelligenceLogisticsScreen> createState() =>
      _IntelligenceLogisticsScreenState();
}

class _IntelligenceTool {
  const _IntelligenceTool(this.kind, this.title, this.subtitle, this.icon);
  final String kind;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _IntelligenceLogisticsScreenState
    extends State<IntelligenceLogisticsScreen> {
  final _db = TradeDatabase.instance;
  final _engine = const FieldIntelligenceService();
  late Future<List<Map<String, dynamic>>> _records = _loadRecords();

  static const _tools = <_IntelligenceTool>[
    _IntelligenceTool(
        'communication',
        'Communication inbox',
        'Keep external messages and files with the supplier',
        Icons.inbox_outlined),
    _IntelligenceTool(
        'sourcing_assistant',
        'Sourcing assistant',
        'Ask plain-language questions across your local records',
        Icons.search_rounded),
    _IntelligenceTool(
        'catalogue_import',
        'Catalogue bulk importer',
        'Turn catalogue pages into reviewed product drafts',
        Icons.menu_book_outlined),
    _IntelligenceTool(
        'field_checkin',
        'Live team coordination',
        'Check into a hall or booth and avoid duplicate visits',
        Icons.groups_2_outlined),
    _IntelligenceTool('dynamic_route', 'Dynamic route replanning',
        'Reorder unfinished booths as priorities change', Icons.route_outlined),
    _IntelligenceTool(
        'tariff_profile',
        'HS code and tariff assistant',
        'Record classification, duty and import requirements',
        Icons.policy_outlined),
    _IntelligenceTool(
        'currency_snapshot',
        'Currency normalization',
        'Compare quotes using dated central-bank rates',
        Icons.currency_exchange),
    _IntelligenceTool(
        'container_plan',
        'Container load calculator',
        'Estimate cartons, units, CBM and payload utilization',
        Icons.inventory_2_outlined),
    _IntelligenceTool(
        'market_readiness',
        'Market-readiness matrix',
        'Check product evidence against each destination market',
        Icons.public_outlined),
    _IntelligenceTool(
        'quality_inspection',
        'AQL quality inspection',
        'Build sampling limits and record inspection results',
        Icons.rule_folder_outlined),
    _IntelligenceTool(
        'supplier_performance',
        'Supplier performance',
        'Score actual delivery, quality, cost and responsiveness',
        Icons.speed_outlined),
    _IntelligenceTool(
        'corrective_action',
        'Claims and corrective actions',
        'Track defects, impact, root cause and closure evidence',
        Icons.report_problem_outlined),
    _IntelligenceTool(
        'offline_transfer',
        'Offline phone transfer',
        'Move compact supplier records with a direct QR code',
        Icons.mobile_screen_share_outlined),
    _IntelligenceTool(
        'fair_glossary',
        'Fair terminology glossary',
        'Keep approved technical and translated terms',
        Icons.translate_outlined),
    _IntelligenceTool(
        'field_readiness',
        'Field-readiness centre',
        'Check storage, sync, review queues and device preparation',
        Icons.health_and_safety_outlined),
  ];

  Future<List<Map<String, dynamic>>> _loadRecords() =>
      _db.queryAll('workflow_items', orderBy: 'updated_at DESC');

  void _refresh() => setState(() => _records = _loadRecords());

  Map<String, dynamic> _data(Map<String, dynamic> row) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(row['data_json'] as String? ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _save({
    required String kind,
    required String title,
    required Map<String, Object?> data,
    String status = 'Open',
    int? tripId,
    int? supplierId,
    int? productId,
    DateTime? dueAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.insert('workflow_items', {
      'kind': kind,
      'trip_id': tripId,
      'exhibitor_id': supplierId,
      'product_id': productId,
      'title': title,
      'status': status,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'data_json': jsonEncode(data),
      'created_at': now,
      'updated_at': now,
    });
    await _db.logAudit('Created ${_title(kind)}', title);
    _refresh();
  }

  String _title(String kind) =>
      _tools.where((tool) => tool.kind == kind).firstOrNull?.title ?? kind;

  Future<Exhibitor?> _pickSupplier(
      {String title = 'Choose supplier', bool allowNone = false}) async {
    final suppliers = await _db.getExhibitors(null);
    if (!mounted) return null;
    return showModalBottomSheet<Exhibitor>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(title)),
          if (allowNone)
            ListTile(
              leading: const Icon(Icons.location_city_outlined),
              title: const Text('Hall or area only'),
              subtitle: const Text('Continue without linking a supplier'),
              onTap: () => Navigator.pop(context),
            ),
          if (suppliers.isEmpty)
            const ListTile(
                title: Text('No suppliers yet'),
                subtitle: Text('Capture a supplier first.')),
          for (final supplier in suppliers)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(supplier.name),
              subtitle: Text([supplier.hall, supplier.booth, supplier.country]
                  .where((value) => value.isNotEmpty)
                  .join(' | ')),
              onTap: () => Navigator.pop(context, supplier),
            ),
        ]),
      ),
    );
  }

  Future<Trip?> _pickTrip() async {
    final trips = await _db.getTrips();
    if (!mounted) return null;
    return showModalBottomSheet<Trip>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Choose trip')),
          for (final trip in trips)
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(trip.name),
              subtitle: Text(trip.city),
              onTap: () => Navigator.pop(context, trip),
            ),
        ]),
      ),
    );
  }

  Future<Product?> _pickProduct(int supplierId) async {
    final products = await _db.getProducts(supplierId);
    if (!mounted) return null;
    return showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Choose product')),
          for (final product in products)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(product.name),
              subtitle: Text(product.modelCode),
              onTap: () => Navigator.pop(context, product),
            ),
        ]),
      ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  Future<String> _saveEvidence(XFile source,
      {required String folder,
      required String ownerType,
      required int ownerId,
      required String note}) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(root.path, folder));
    await directory.create(recursive: true);
    final target = path.join(directory.path,
        '${DateTime.now().microsecondsSinceEpoch}${path.extension(source.path)}');
    await File(source.path).copy(target);
    await _db.insert(
        'attachments',
        Attachment(
                ownerType: ownerType,
                ownerId: ownerId,
                kind: 'image',
                path: target,
                note: note,
                createdAt: DateTime.now())
            .toMap()
          ..remove('id'));
    return target;
  }

  String _displayKey(String value) => value
      .split('_')
      .map((part) => part.isEmpty
          ? part
          : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<void> _showHistory(String kind) async {
    final rows =
        (await _loadRecords()).where((row) => row['kind'] == kind).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_title(kind),
                      style: Theme.of(context).textTheme.titleLarge)),
            ),
            const Divider(),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      title: 'No saved records',
                      message:
                          'Complete the workflow to create the first record.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final row in rows)
                          Card(
                            child: ExpansionTile(
                              title: Text(row['title'] as String),
                              subtitle: Text(row['status'] as String),
                              children: [
                                for (final entry in _data(row).entries)
                                  if (entry.value != null &&
                                      entry.value.toString().isNotEmpty)
                                    ListTile(
                                      dense: true,
                                      title: Text(_displayKey(entry.key)),
                                      subtitle: SelectableText(entry.value
                                                  is Map ||
                                              entry.value is List
                                          ? const JsonEncoder.withIndent('  ')
                                              .convert(entry.value)
                                          : entry.value.toString()),
                                    ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final complete =
                                            row['status'] == 'Completed' ||
                                                row['status'] == 'Closed';
                                        await _db.update('workflow_items',
                                            row['id'] as int, {
                                          'status':
                                              complete ? 'Open' : 'Completed',
                                          'updated_at': DateTime.now()
                                              .toUtc()
                                              .toIso8601String(),
                                        });
                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }
                                        _refresh();
                                      },
                                      icon: Icon(row['status'] == 'Completed'
                                          ? Icons.undo
                                          : Icons.check),
                                      label: Text(row['status'] == 'Completed'
                                          ? 'Reopen'
                                          : 'Mark complete'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _open(_IntelligenceTool tool) => switch (tool.kind) {
        'communication' => _communicationInbox(),
        'sourcing_assistant' => _assistant(),
        'catalogue_import' => _catalogueImport(),
        'field_checkin' => _teamCoordination(),
        'dynamic_route' => _dynamicRoute(),
        'tariff_profile' => _tariffAssistant(),
        'currency_snapshot' => _currencyComparison(),
        'container_plan' => _containerCalculator(),
        'market_readiness' => _marketReadiness(),
        'quality_inspection' => _qualityInspection(),
        'supplier_performance' => _supplierPerformance(),
        'corrective_action' => _correctiveAction(),
        'offline_transfer' => _offlineTransfer(),
        'fair_glossary' => _glossary(),
        'field_readiness' => _readiness(),
        _ => Future.value(),
      };

  Future<void> _communicationInbox() async {
    final rows = (await _loadRecords())
        .where((row) => row['kind'] == 'communication')
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Text('Communication inbox',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _addCommunication();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ]),
            ),
            const Divider(),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Inbox is empty',
                      message:
                          'Add an email, chat export, message, or shared document.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final data = _data(row);
                        return Card(
                          child: ExpansionTile(
                            leading: Icon(switch (data['channel']) {
                              'Email' => Icons.email_outlined,
                              'WhatsApp' => Icons.chat_outlined,
                              'WeChat' => Icons.forum_outlined,
                              _ => Icons.description_outlined,
                            }),
                            title: Text(row['title'] as String),
                            subtitle: Text(
                                '${data['channel'] ?? 'Message'} | ${data['supplier'] ?? 'Unlinked'}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText(
                                    data['body']?.toString() ??
                                        'No message text.'),
                              ),
                              if ((data['source_path']?.toString() ?? '')
                                  .isNotEmpty)
                                ListTile(
                                  leading: const Icon(Icons.attach_file),
                                  title:
                                      Text(path.basename(data['source_path'])),
                                  subtitle: const Text('Imported source file'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _addCommunication() async {
    final supplier = await _pickSupplier(title: 'Link message to supplier');
    if (supplier == null || !mounted) return;
    final subject = TextEditingController();
    final body = TextEditingController();
    var channel = 'Email';
    String? sourcePath;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add communication'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: channel,
                decoration: const InputDecoration(labelText: 'Channel'),
                items: ['Email', 'WhatsApp', 'WeChat', 'Document', 'Other']
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => channel = value ?? channel,
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: subject,
                  decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 10),
              TextField(
                  controller: body,
                  minLines: 4,
                  maxLines: 10,
                  decoration:
                      const InputDecoration(labelText: 'Message or notes')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  const picker = MethodChannel('canton_fair_crm/backup');
                  final picked =
                      await picker.invokeMethod<String>('pickDocument');
                  if (picked == null) return;
                  final root = await getApplicationDocumentsDirectory();
                  final folder =
                      Directory(path.join(root.path, 'communication_inbox'));
                  await folder.create(recursive: true);
                  final target = path.join(folder.path,
                      '${DateTime.now().microsecondsSinceEpoch}_${path.basename(picked)}');
                  await File(picked).copy(target);
                  sourcePath = target;
                  final extension = path.extension(target).toLowerCase();
                  if (['.txt', '.csv', '.json'].contains(extension)) {
                    final text = await File(target).readAsString();
                    if (body.text.trim().isEmpty) body.text = text;
                  }
                  setDialogState(() {});
                },
                icon:
                    Icon(sourcePath == null ? Icons.attach_file : Icons.check),
                label: Text(sourcePath == null
                    ? 'Import message or document'
                    : path.basename(sourcePath!)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save == true &&
        (subject.text.trim().isNotEmpty ||
            body.text.trim().isNotEmpty ||
            sourcePath != null)) {
      await _save(
        kind: 'communication',
        title: subject.text.trim().isEmpty
            ? '$channel from ${supplier.name}'
            : subject.text.trim(),
        supplierId: supplier.id,
        data: {
          'supplier': supplier.name,
          'channel': channel,
          'body': body.text.trim(),
          'source_path': sourcePath,
          'received_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (sourcePath != null && await File(sourcePath!).exists()) {
        await _db.insert(
            'attachments',
            Attachment(
                    ownerType: 'exhibitor',
                    ownerId: supplier.id!,
                    kind: 'document',
                    path: sourcePath!,
                    note: '$channel communication: ${subject.text.trim()}',
                    createdAt: DateTime.now())
                .toMap()
              ..remove('id'));
      }
    }
    subject.dispose();
    body.dispose();
  }

  Future<void> _assistant() async {
    final query = TextEditingController();
    String? answer;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Ask your sourcing records',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Try: shortlisted China suppliers, overdue tasks, quotes below 10 USD, or certificates expiring.'),
              const SizedBox(height: 12),
              TextField(
                controller: query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                    labelText: 'Question', prefixIcon: Icon(Icons.search)),
                onSubmitted: (_) async {
                  answer = await _answerQuery(query.text);
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  answer = await _answerQuery(query.text);
                  setSheetState(() {});
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Search records'),
              ),
              if (answer != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 320),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(child: SelectableText(answer!)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    query.dispose();
  }

  Future<String> _answerQuery(String raw) async {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return 'Enter a question first.';
    final suppliers = await _db.getExhibitors(null);
    final products =
        (await _db.queryAll('products')).map(Product.fromMap).toList();
    final quotes = (await _db.queryAll('quotes')).map(Quote.fromMap).toList();
    final meetings = await _db.getMeetings();
    final results = <String>[];
    final priceMatch = RegExp(r'(?:below|under|less than)\s*(\d+(?:\.\d+)?)')
        .firstMatch(query);
    if (query.contains('overdue') ||
        query.contains('task') ||
        query.contains('follow')) {
      final now = DateTime.now();
      for (final meeting in meetings.where((item) =>
          !item.completed &&
          item.followUpDate != null &&
          item.followUpDate!.isBefore(now))) {
        final supplier = suppliers
            .where((item) => item.id == meeting.exhibitorId)
            .firstOrNull;
        results.add(
            'OVERDUE: ${supplier?.name ?? 'Supplier'} - ${meeting.outcome}');
      }
    } else if (query.contains('certificate') || query.contains('compliance')) {
      final limit = DateTime.now().add(const Duration(days: 90));
      for (final supplier in suppliers) {
        try {
          final verification = jsonDecode(supplier.verificationJson) as Map;
          for (final rawCertificate
              in verification['certificates'] as List? ?? const []) {
            final certificate = rawCertificate as Map;
            final expiry =
                DateTime.tryParse(certificate['expiry']?.toString() ?? '');
            if (certificate['verified'] != true ||
                (expiry != null && expiry.isBefore(limit))) {
              results.add(
                  '${supplier.name}: ${certificate['type'] ?? 'Certificate'} - ${certificate['verified'] == true ? 'expires ${expiry?.toString().split(' ').first}' : 'not verified'}');
            }
          }
        } catch (_) {
          results.add('${supplier.name}: verification record needs review');
        }
      }
    } else if (query.contains('quote') ||
        query.contains('price') ||
        priceMatch != null) {
      final limit = double.tryParse(priceMatch?.group(1) ?? '');
      for (final quote in quotes.where((item) =>
          item.unitPrice != null &&
          (limit == null || item.unitPrice! < limit))) {
        final product =
            products.where((item) => item.id == quote.productId).firstOrNull;
        final supplier = suppliers
            .where((item) => item.id == product?.exhibitorId)
            .firstOrNull;
        results.add(
            '${supplier?.name ?? 'Supplier'} | ${product?.name ?? 'Product'} | ${quote.unitPrice} ${quote.currency} | MOQ ${quote.moq ?? '-'}');
      }
    } else {
      final words =
          query.split(RegExp(r'\s+')).where((word) => word.length > 2).toList();
      for (final supplier in suppliers) {
        final text =
            '${supplier.name} ${supplier.country} ${supplier.category} ${supplier.booth} ${supplier.contactCompanyNotes}'
                .toLowerCase();
        final matchesWords = words.every((word) =>
            [
              'supplier',
              'suppliers',
              'show',
              'find',
              'which',
              'from',
              'shortlist',
              'shortlisted'
            ].contains(word) ||
            text.contains(word));
        final matchesShortlist =
            !query.contains('shortlist') || supplier.shortlisted;
        if (matchesWords && matchesShortlist) {
          results.add(
              '${supplier.name} | ${supplier.country} | ${supplier.hall} ${supplier.booth} | score ${supplier.decisionScore.round()}');
        }
      }
    }
    if (results.isEmpty) {
      return 'No matching records were found. Try a supplier country, category, quote limit, overdue task, or certificate question.';
    }
    return '${results.length} result${results.length == 1 ? '' : 's'}\n\n${results.take(50).join('\n')}';
  }

  Future<void> _catalogueImport() async {
    final supplier = await _pickSupplier(title: 'Catalogue supplier');
    if (supplier == null || !mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          const ListTile(
              title: Text('Import catalogue'),
              subtitle: Text('Every extracted page remains reviewable.')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Select page images'),
              subtitle:
                  const Text('Best for automatic on-device text extraction'),
              onTap: () => Navigator.pop(context, 'images')),
          ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Attach PDF catalogue'),
              subtitle: const Text(
                  'Keep the original and create product drafts manually'),
              onTap: () => Navigator.pop(context, 'pdf')),
        ]),
      ),
    );
    if (action == 'images') return _importCatalogueImages(supplier);
    if (action == 'pdf') return _attachCataloguePdf(supplier);
  }

  Future<void> _importCatalogueImages(Exhibitor supplier) async {
    final images = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (images.isEmpty) return;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(path.join(root.path, 'catalogue_imports'));
    await folder.create(recursive: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    var created = 0;
    try {
      for (var index = 0; index < images.length; index++) {
        final target = path.join(folder.path,
            '${DateTime.now().microsecondsSinceEpoch}_$index${path.extension(images[index].path)}');
        await File(images[index].path).copy(target);
        final text =
            (await recognizer.processImage(InputImage.fromFilePath(target)))
                .text;
        final lines = text
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final name = lines.firstOrNull ?? 'Catalogue page ${index + 1}';
        final productId = await _db.insert(
            'products',
            Product(
              exhibitorId: supplier.id!,
              name: name.length > 80 ? name.substring(0, 80) : name,
              specs: text,
              detailsJson: jsonEncode({
                'catalogue_page': index + 1,
                'source_path': target,
                'review_status': 'Needs review'
              }),
            ).toMap()
              ..remove('id'));
        await _db.insert(
            'attachments',
            Attachment(
                    ownerType: 'product',
                    ownerId: productId,
                    kind: 'image',
                    path: target,
                    note: 'Catalogue page ${index + 1}',
                    createdAt: DateTime.now())
                .toMap()
              ..remove('id'));
        created++;
      }
    } finally {
      await recognizer.close();
    }
    await _save(
        kind: 'catalogue_import',
        title: supplier.name,
        supplierId: supplier.id,
        status: 'Needs review',
        data: {'pages': images.length, 'product_drafts': created});
    _message('$created product drafts created for review.');
  }

  Future<void> _attachCataloguePdf(Exhibitor supplier) async {
    const picker = MethodChannel('canton_fair_crm/backup');
    final picked = await picker.invokeMethod<String>('pickDocument');
    if (picked == null) return;
    if (path.extension(picked).toLowerCase() != '.pdf') {
      _message('Choose a PDF file for catalogue PDF processing.');
      return;
    }
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(path.join(root.path, 'catalogue_imports'));
    await folder.create(recursive: true);
    final target = path.join(folder.path,
        '${DateTime.now().microsecondsSinceEpoch}_${path.basename(picked)}');
    await File(picked).copy(target);
    await _db.insert(
        'attachments',
        Attachment(
                ownerType: 'exhibitor',
                ownerId: supplier.id!,
                kind: 'document',
                path: target,
                note: 'PDF catalogue awaiting product review',
                createdAt: DateTime.now())
            .toMap()
          ..remove('id'));
    final pageFolder = Directory(
        path.join(folder.path, 'pdf_${DateTime.now().microsecondsSinceEpoch}'));
    List<String>? rendered;
    try {
      rendered = await const MethodChannel('canton_fair_crm/pdf')
          .invokeListMethod<String>('renderPages', {
        'path': target,
        'output': pageFolder.path,
        'maxPages': 30,
      });
    } on PlatformException catch (error) {
      _message(
          'The PDF could not be rendered: ${error.message ?? 'invalid PDF'}');
      return;
    }
    final pages = rendered ?? const <String>[];
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    var drafts = 0;
    try {
      for (var index = 0; index < pages.length; index++) {
        final text = (await recognizer
                .processImage(InputImage.fromFilePath(pages[index])))
            .text;
        final lines = text
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final rawName = lines.firstOrNull ?? 'Catalogue page ${index + 1}';
        final productId = await _db.insert(
            'products',
            Product(
              exhibitorId: supplier.id!,
              name: rawName.length > 80 ? rawName.substring(0, 80) : rawName,
              specs: text,
              detailsJson: jsonEncode({
                'catalogue_page': index + 1,
                'source_pdf': target,
                'page_image': pages[index],
                'review_status': 'Needs review',
              }),
            ).toMap()
              ..remove('id'));
        await _db.insert(
            'attachments',
            Attachment(
                    ownerType: 'product',
                    ownerId: productId,
                    kind: 'image',
                    path: pages[index],
                    note: 'Rendered catalogue page ${index + 1}',
                    createdAt: DateTime.now())
                .toMap()
              ..remove('id'));
        drafts++;
      }
    } finally {
      await recognizer.close();
    }
    await _save(
        kind: 'catalogue_import',
        title: supplier.name,
        supplierId: supplier.id,
        status: 'Needs review',
        data: {
          'pdf_path': target,
          'pages_processed': pages.length,
          'product_drafts': drafts,
        });
    _message('$drafts PDF pages converted into product drafts for review.');
  }

  Future<void> _teamCoordination() async {
    final records = (await _loadRecords())
        .where((row) =>
            row['kind'] == 'field_checkin' && row['status'] == 'Active')
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Text('Team field board',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _checkIn();
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Check in'),
                ),
              ]),
            ),
            const Divider(),
            Expanded(
              child: records.isEmpty
                  ? const EmptyState(
                      icon: Icons.groups_2_outlined,
                      title: 'Nobody is checked in',
                      message:
                          'Check in before starting a hall or booth visit.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final row in records)
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child:
                                      Icon(Icons.person_pin_circle_outlined)),
                              title: Text(row['title'] as String),
                              subtitle: Text([
                                _data(row)['location']?.toString() ?? '',
                                _data(row)['supplier']?.toString() ?? '',
                                _data(row)['activity']?.toString() ?? '',
                              ].where((value) => value.isNotEmpty).join(' | ')),
                              trailing: IconButton(
                                tooltip: 'End check-in',
                                icon: const Icon(Icons.stop_circle_outlined),
                                onPressed: () async {
                                  await _db.update(
                                      'workflow_items', row['id'] as int, {
                                    'status': 'Completed',
                                    'updated_at': DateTime.now()
                                        .toUtc()
                                        .toIso8601String(),
                                  });
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  _refresh();
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _checkIn() async {
    final supplier =
        await _pickSupplier(title: 'Optional booth supplier', allowNone: true);
    if (!mounted) return;
    final hall = TextEditingController(text: supplier?.hall ?? '');
    final booth = TextEditingController(text: supplier?.booth ?? '');
    final activity = TextEditingController(text: 'Supplier visit');
    final user = Supabase.instance.client.auth.currentUser;
    final owner = user?.email ?? user?.id ?? 'Local user';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Field check-in'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: hall,
                decoration: const InputDecoration(labelText: 'Hall')),
            const SizedBox(height: 10),
            TextField(
                controller: booth,
                decoration: const InputDecoration(labelText: 'Booth or area')),
            const SizedBox(height: 10),
            TextField(
                controller: activity,
                decoration: const InputDecoration(labelText: 'Activity')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Check in')),
        ],
      ),
    );
    if (save == true) {
      final duplicates = (await _loadRecords()).where((row) {
        if (row['kind'] != 'field_checkin' || row['status'] != 'Active') {
          return false;
        }
        final data = _data(row);
        return supplier != null &&
            data['supplier_id'] == supplier.id &&
            data['owner'] != owner;
      });
      await _save(
        kind: 'field_checkin',
        title: owner,
        supplierId: supplier?.id,
        tripId: supplier?.tripId,
        status: 'Active',
        data: {
          'owner': owner,
          'supplier_id': supplier?.id,
          'supplier': supplier?.name,
          'location': [hall.text.trim(), booth.text.trim()]
              .where((value) => value.isNotEmpty)
              .join(' '),
          'activity': activity.text.trim(),
          'checked_in_at': DateTime.now().toUtc().toIso8601String(),
          'possible_duplicate_visit': duplicates.isNotEmpty,
        },
      );
      if (duplicates.isNotEmpty) {
        _message('Another teammate is already checked into this supplier.');
      }
    }
    hall.dispose();
    booth.dispose();
    activity.dispose();
  }

  Future<void> _dynamicRoute() async {
    final trip = await _pickTrip();
    if (trip == null || !mounted) return;
    final suppliers = await _db.getExhibitors(trip.id);
    final ordered = _engine.reorderRoute(suppliers,
        hall: (supplier) => supplier.hall,
        booth: (supplier) => supplier.booth,
        priority: (supplier) =>
            (supplier.shortlisted ? 5 : 0) +
            supplier.rating +
            (supplier.decision == 'Yes' ? 3 : 0),
        completed: (supplier) => supplier.visitedAt != null);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Replanned route',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(trip.name),
                    ])),
                IconButton(
                    tooltip: 'Share route',
                    icon: const Icon(Icons.ios_share_outlined),
                    onPressed: () => SharePlus.instance.share(ShareParams(
                        text: ordered
                            .where((supplier) => supplier.visitedAt == null)
                            .map((supplier) =>
                                '${supplier.hall} ${supplier.booth} - ${supplier.name}')
                            .join('\n')))),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ordered.isEmpty
                  ? const EmptyState(
                      icon: Icons.route_outlined,
                      title: 'No route stops',
                      message: 'Add suppliers with hall and booth details.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: ordered.length,
                      itemBuilder: (context, index) {
                        final supplier = ordered[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${index + 1}')),
                            title: Text(supplier.name),
                            subtitle: Text(
                                '${supplier.hall} ${supplier.booth} | ${supplier.category.isEmpty ? 'No category' : supplier.category}'),
                            trailing: supplier.visitedAt != null
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.teal)
                                : InfoChip(
                                    label: supplier.shortlisted
                                        ? 'Priority'
                                        : 'Planned',
                                    color: supplier.shortlisted
                                        ? AppColors.amber
                                        : AppColors.teal),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  (String, String) _suggestHs(String text) {
    final value = text.toLowerCase();
    const rules = <String, (String, String)>{
      'furniture': ('9403', 'Other furniture and parts'),
      'chair': ('9401', 'Seats and parts'),
      'lamp': ('9405', 'Lamps and lighting fittings'),
      'light': ('9405', 'Lamps and lighting fittings'),
      'shoe': ('6403', 'Footwear with outer soles of rubber/plastics/leather'),
      'garment': ('6204', 'Selected non-knitted garments'),
      'clothing': ('6204', 'Selected non-knitted garments'),
      'toy': ('9503', 'Toys, scale models and puzzles'),
      'ceramic': ('6912', 'Ceramic tableware and household articles'),
      'battery': ('8507', 'Electric accumulators'),
      'motor': ('8501', 'Electric motors and generators'),
      'pump': ('8413', 'Pumps for liquids'),
      'plastic': ('3926', 'Other articles of plastics'),
      'steel': ('7326', 'Other articles of iron or steel'),
      'textile': ('6307', 'Other made-up textile articles'),
    };
    for (final entry in rules.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return (
      '',
      'No offline suggestion. Confirm classification with a customs specialist.'
    );
  }

  Future<void> _tariffAssistant() async {
    final supplier = await _pickSupplier(title: 'Product supplier');
    if (supplier == null) return;
    final product = await _pickProduct(supplier.id!);
    if (product == null || !mounted) return;
    final suggestion =
        _suggestHs('${product.name} ${product.specs} ${supplier.category}');
    final hs = TextEditingController(text: suggestion.$1);
    final destination = TextEditingController(text: 'United Arab Emirates');
    final duty = TextEditingController();
    final requirements = TextEditingController(text: suggestion.$2);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tariff classification review'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InfoChip(label: product.name, icon: Icons.inventory_2_outlined),
            const SizedBox(height: 12),
            TextField(
                controller: hs,
                decoration:
                    const InputDecoration(labelText: 'HS code suggestion')),
            const SizedBox(height: 10),
            TextField(
                controller: destination,
                decoration:
                    const InputDecoration(labelText: 'Destination market')),
            const SizedBox(height: 10),
            TextField(
                controller: duty,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Estimated duty percent')),
            const SizedBox(height: 10),
            TextField(
                controller: requirements,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Import documents and classification notes')),
            const SizedBox(height: 8),
            const Text(
                'HS suggestions are starting points. Confirm the final code and duty with the destination customs authority.'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save profile')),
        ],
      ),
    );
    if (save == true) {
      await _save(
          kind: 'tariff_profile',
          title: '${product.name} - ${destination.text.trim()}',
          supplierId: supplier.id,
          productId: product.id,
          data: {
            'hs_code': hs.text.trim(),
            'destination': destination.text.trim(),
            'duty_percent': double.tryParse(duty.text.trim()),
            'requirements': requirements.text.trim(),
            'verification_status': 'Needs customs confirmation',
          });
    }
    hs.dispose();
    destination.dispose();
    duty.dispose();
    requirements.dispose();
  }

  Future<void> _currencyComparison() async {
    CurrencySnapshot? snapshot;
    Object? error;
    try {
      snapshot = await _engine.latestRates();
    } catch (caught) {
      error = caught;
    }
    final target = TextEditingController(text: 'USD');
    if (!mounted) return;
    if (snapshot == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rates unavailable'),
          content: Text(
              'Could not retrieve the latest European Central Bank reference rates.\n\n$error'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ],
        ),
      );
      target.dispose();
      return;
    }
    final products =
        (await _db.queryAll('products')).map(Product.fromMap).toList();
    final suppliers = await _db.getExhibitors(null);
    final quotes = (await _db.queryAll('quotes'))
        .map(Quote.fromMap)
        .where((quote) => quote.unitPrice != null)
        .toList();
    if (!mounted) return;
    String selectedTarget = 'USD';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final supported = ['USD', 'CNY', 'AED', 'EUR', 'GBP'];
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Normalized quotes',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                              'ECB reference date ${snapshot!.date.toString().split(' ').first}'),
                        ])),
                    DropdownButton<String>(
                      value: selectedTarget,
                      items: supported
                          .where((currency) =>
                              currency == 'EUR' ||
                              snapshot!.perEuro.containsKey(currency))
                          .map((currency) => DropdownMenuItem(
                              value: currency, child: Text(currency)))
                          .toList(),
                      onChanged: (value) => setSheetState(
                          () => selectedTarget = value ?? selectedTarget),
                    ),
                  ]),
                ),
                const Divider(),
                Expanded(
                  child: quotes.isEmpty
                      ? const EmptyState(
                          icon: Icons.currency_exchange,
                          title: 'No priced quotes',
                          message:
                              'Add supplier quotes before normalizing currencies.')
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: quotes.length,
                          itemBuilder: (context, index) {
                            final quote = quotes[index];
                            final product = products
                                .where((item) => item.id == quote.productId)
                                .firstOrNull;
                            final supplier = suppliers
                                .where(
                                    (item) => item.id == product?.exhibitorId)
                                .firstOrNull;
                            String converted;
                            try {
                              converted = snapshot!
                                  .convert(quote.unitPrice!, quote.currency,
                                      selectedTarget)
                                  .toStringAsFixed(2);
                            } catch (_) {
                              converted = 'Unavailable';
                            }
                            return Card(
                                child: ListTile(
                              title: Text(
                                  '${supplier?.name ?? 'Supplier'} - ${product?.name ?? quote.label}'),
                              subtitle: Text(
                                  '${quote.unitPrice} ${quote.currency} | MOQ ${quote.moq ?? '-'}'),
                              trailing: Text('$converted\n$selectedTarget',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ));
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    await _save(
        kind: 'currency_snapshot',
        title: 'ECB ${snapshot.date.toString().split(' ').first}',
        status: 'Reference',
        data: {
          'date': snapshot.date.toIso8601String(),
          'base': 'EUR',
          'rates': snapshot.perEuro
        });
    target.dispose();
  }

  Future<void> _containerCalculator() async {
    final controllers = {
      'length': TextEditingController(),
      'width': TextEditingController(),
      'height': TextEditingController(),
      'weight': TextEditingController(),
      'units': TextEditingController(text: '1'),
      'cbm': TextEditingController(text: '67'),
      'payload': TextEditingController(text: '26500'),
    };
    Map<String, num>? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Container load plan',
                        style: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final entry in [
                    ('length', 'Length cm'),
                    ('width', 'Width cm'),
                    ('height', 'Height cm')
                  ])
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: TextField(
                                controller: controllers[entry.$1],
                                keyboardType: TextInputType.number,
                                decoration:
                                    InputDecoration(labelText: entry.$2)))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: controllers['weight'],
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Carton kg'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: controllers['units'],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Units/carton'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: controllers['cbm'],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Container CBM'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: controllers['payload'],
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Payload kg'))),
                ]),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    try {
                      result = _engine.containerLoad(
                          cartonLengthCm:
                              double.parse(controllers['length']!.text),
                          cartonWidthCm:
                              double.parse(controllers['width']!.text),
                          cartonHeightCm:
                              double.parse(controllers['height']!.text),
                          cartonWeightKg:
                              double.parse(controllers['weight']!.text),
                          unitsPerCarton: int.parse(controllers['units']!.text),
                          containerCbm: double.parse(controllers['cbm']!.text),
                          payloadKg:
                              double.parse(controllers['payload']!.text));
                      setSheetState(() {});
                    } catch (_) {
                      _message(
                          'Enter valid positive carton and container values.');
                    }
                  },
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calculate'),
                ),
                if (result != null) ...[
                  const SizedBox(height: 16),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            _ResultRow('Recommended cartons',
                                '${result!['recommended_cartons']}'),
                            _ResultRow('Total units',
                                '${result!['recommended_units']}'),
                            _ResultRow('Used volume',
                                '${(result!['used_cbm'] as num).toStringAsFixed(2)} CBM'),
                            _ResultRow('Used payload',
                                '${(result!['used_weight_kg'] as num).toStringAsFixed(0)} kg'),
                          ]))),
                  FilledButton.tonal(
                      onPressed: () async {
                        await _save(
                            kind: 'container_plan',
                            title: '${result!['recommended_units']} units',
                            status: 'Calculated',
                            data: {
                              ...result!,
                              'inputs': {
                                for (final entry in controllers.entries)
                                  entry.key: entry.value.text
                              }
                            });
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Save plan')),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _marketReadiness() async {
    final supplier = await _pickSupplier();
    if (supplier == null) return;
    final product = await _pickProduct(supplier.id!);
    if (product == null || !mounted) return;
    final market = TextEditingController(text: 'United Arab Emirates');
    final notes = TextEditingController();
    final certificateNames = <String>[];
    var hasCurrentVerifiedCertificate = false;
    try {
      final verification = jsonDecode(supplier.verificationJson) as Map;
      for (final raw in verification['certificates'] as List? ?? const []) {
        final certificate = raw as Map;
        final expiry =
            DateTime.tryParse(certificate['expiry']?.toString() ?? '');
        certificateNames.add(certificate['type']?.toString() ?? 'Certificate');
        if (certificate['verified'] == true &&
            (expiry == null || expiry.isAfter(DateTime.now()))) {
          hasCurrentVerifiedCertificate = true;
        }
      }
    } catch (_) {
      // Legacy records remain available for manual checklist review.
    }
    final checks = <String, bool>{
      'Product classification confirmed': false,
      'Required certificates valid': hasCurrentVerifiedCertificate,
      'Label and language compliant': false,
      'Safety test reports available': false,
      'Importer documents prepared': false,
      'Restricted substances reviewed': false,
    };
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Market-readiness review'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: market,
                decoration:
                    const InputDecoration(labelText: 'Destination market')),
            if (certificateNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Text('Supplier register: ${certificateNames.join(', ')}'),
                ),
              ),
            const SizedBox(height: 8),
            for (final entry in checks.entries)
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: entry.value,
                  title: Text(entry.key),
                  onChanged: (value) =>
                      setDialogState(() => checks[entry.key] = value ?? false)),
            TextField(
                controller: notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Missing evidence and notes')),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save review')),
          ],
        ),
      ),
    );
    if (save == true) {
      final passed = checks.values.where((value) => value).length;
      await _save(
          kind: 'market_readiness',
          title: '${product.name} - ${market.text.trim()}',
          supplierId: supplier.id,
          productId: product.id,
          status: passed == checks.length ? 'Ready' : 'Needs attention',
          data: {
            'market': market.text.trim(),
            'checks': checks,
            'passed': passed,
            'total': checks.length,
            'notes': notes.text.trim()
          });
    }
    market.dispose();
    notes.dispose();
  }

  Future<void> _qualityInspection() async {
    final supplier = await _pickSupplier();
    if (supplier == null) return;
    final product = await _pickProduct(supplier.id!);
    if (product == null || !mounted) return;
    final lot = TextEditingController();
    var level = 'II';
    final critical = TextEditingController(text: '0');
    final major = TextEditingController(text: '0');
    final minor = TextEditingController(text: '0');
    final notes = TextEditingController();
    XFile? evidence;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AQL inspection'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: lot,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Production lot size')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                initialValue: level,
                items: ['I', 'II', 'III']
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text('General level $value')))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => level = value ?? level),
                decoration:
                    const InputDecoration(labelText: 'Inspection level')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: critical,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Critical found'))),
              const SizedBox(width: 6),
              Expanded(
                  child: TextField(
                      controller: major,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Major found'))),
              const SizedBox(width: 6),
              Expanded(
                  child: TextField(
                      controller: minor,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Minor found'))),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Inspection evidence and notes')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final image = await CameraCaptureService.capture(() =>
                    ImagePicker().pickImage(
                        source: ImageSource.camera, imageQuality: 88));
                if (image != null) {
                  setDialogState(() => evidence = image);
                }
              },
              icon: Icon(
                  evidence == null ? Icons.camera_alt_outlined : Icons.check),
              label: Text(evidence == null
                  ? 'Photograph inspection evidence'
                  : 'Evidence ready'),
            ),
            const SizedBox(height: 8),
            const Text(
                'Sampling and defect limits are planning guidance. Confirm the final inspection plan against your agreed ISO 2859-1 / ANSI Z1.4 table and product specification.'),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Calculate and save')),
          ],
        ),
      ),
    );
    final lotSize = int.tryParse(lot.text.trim());
    if (save == true && lotSize != null && lotSize > 0) {
      final sample = _engine.aqlSampleSize(lotSize, level: level);
      final limits = _engine.defectLimits(sample);
      final found = {
        'critical': int.tryParse(critical.text) ?? 0,
        'major': int.tryParse(major.text) ?? 0,
        'minor': int.tryParse(minor.text) ?? 0
      };
      final passed =
          found.entries.every((entry) => entry.value <= limits[entry.key]!);
      await _save(
          kind: 'quality_inspection',
          title: '${product.name} - lot $lotSize',
          supplierId: supplier.id,
          productId: product.id,
          status: passed ? 'Passed' : 'Failed',
          data: {
            'lot_size': lotSize,
            'inspection_level': level,
            'sample_size': sample,
            'acceptance_limits': limits,
            'defects_found': found,
            'notes': notes.text.trim()
          });
      if (evidence != null) {
        await _saveEvidence(evidence!,
            folder: 'quality_evidence',
            ownerType: 'product',
            ownerId: product.id!,
            note: 'AQL inspection evidence - lot $lotSize');
      }
      _message(
          'Sample $sample units. Inspection ${passed ? 'passed' : 'failed'}.');
    }
    lot.dispose();
    critical.dispose();
    major.dispose();
    minor.dispose();
    notes.dispose();
  }

  Future<void> _supplierPerformance() async {
    final supplier = await _pickSupplier(title: 'Supplier to score');
    if (supplier == null || !mounted) return;
    var quality = 3.0;
    var delivery = 3.0;
    var cost = 3.0;
    var response = 3.0;
    var documentation = 3.0;
    final order = TextEditingController();
    final notes = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post-order performance'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: order,
                decoration: const InputDecoration(
                    labelText: 'PO or shipment reference')),
            _ScoreSlider('Delivered quality', quality,
                (value) => setDialogState(() => quality = value)),
            _ScoreSlider('On-time delivery', delivery,
                (value) => setDialogState(() => delivery = value)),
            _ScoreSlider('Cost accuracy', cost,
                (value) => setDialogState(() => cost = value)),
            _ScoreSlider('Responsiveness', response,
                (value) => setDialogState(() => response = value)),
            _ScoreSlider('Documentation', documentation,
                (value) => setDialogState(() => documentation = value)),
            TextField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Evidence and lessons learned')),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save scorecard')),
          ],
        ),
      ),
    );
    if (save == true) {
      final overall =
          (quality + delivery + cost + response + documentation) / 5;
      await _save(
          kind: 'supplier_performance',
          title:
              '${supplier.name} - ${order.text.trim().isEmpty ? 'Performance review' : order.text.trim()}',
          supplierId: supplier.id,
          status: overall >= 4
              ? 'Preferred'
              : overall >= 3
                  ? 'Acceptable'
                  : 'Needs improvement',
          data: {
            'order_reference': order.text.trim(),
            'quality': quality,
            'delivery': delivery,
            'cost_accuracy': cost,
            'responsiveness': response,
            'documentation': documentation,
            'overall': overall,
            'notes': notes.text.trim(),
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          });
    }
    order.dispose();
    notes.dispose();
  }

  Future<void> _correctiveAction() async {
    final supplier = await _pickSupplier(title: 'Claim supplier');
    if (supplier == null || !mounted) return;
    final reference = TextEditingController();
    final issue = TextEditingController();
    final impact = TextEditingController();
    final rootCause = TextEditingController();
    final corrective = TextEditingController();
    final owner = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    var severity = 'Major';
    XFile? evidence;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Claim and corrective action'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: reference,
                decoration: const InputDecoration(
                    labelText: 'PO / shipment / sample reference')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                initialValue: severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: ['Critical', 'Major', 'Minor']
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => severity = value ?? severity),
            const SizedBox(height: 10),
            TextField(
                controller: issue,
                minLines: 2,
                maxLines: 5,
                decoration:
                    const InputDecoration(labelText: 'Defect or claim')),
            const SizedBox(height: 10),
            TextField(
                controller: impact,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Quantity and financial impact')),
            const SizedBox(height: 10),
            TextField(
                controller: rootCause,
                minLines: 2,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Supplier root cause')),
            const SizedBox(height: 10),
            TextField(
                controller: corrective,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Corrective and preventive action')),
            const SizedBox(height: 10),
            TextField(
                controller: owner,
                decoration: const InputDecoration(labelText: 'Action owner')),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Response due'),
                subtitle: Text(due.toString().split(' ').first),
                onTap: () async {
                  final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: due);
                  if (picked != null) setDialogState(() => due = picked);
                }),
            OutlinedButton.icon(
              onPressed: () async {
                final image = await CameraCaptureService.capture(() =>
                    ImagePicker().pickImage(
                        source: ImageSource.camera, imageQuality: 88));
                if (image != null) {
                  setDialogState(() => evidence = image);
                }
              },
              icon: Icon(
                  evidence == null ? Icons.camera_alt_outlined : Icons.check),
              label: Text(evidence == null
                  ? 'Photograph claim evidence'
                  : 'Evidence ready'),
            ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open claim')),
          ],
        ),
      ),
    );
    if (save == true && issue.text.trim().isNotEmpty) {
      await _save(
          kind: 'corrective_action',
          title:
              '${supplier.name} - ${reference.text.trim().isEmpty ? severity : reference.text.trim()}',
          supplierId: supplier.id,
          status: 'Open',
          dueAt: due,
          data: {
            'reference': reference.text.trim(),
            'severity': severity,
            'issue': issue.text.trim(),
            'impact': impact.text.trim(),
            'root_cause': rootCause.text.trim(),
            'corrective_action': corrective.text.trim(),
            'owner': owner.text.trim(),
            'opened_at': DateTime.now().toUtc().toIso8601String(),
          });
      if (evidence != null) {
        await _saveEvidence(evidence!,
            folder: 'claim_evidence',
            ownerType: 'exhibitor',
            ownerId: supplier.id!,
            note:
                'Claim evidence - ${reference.text.trim().isEmpty ? severity : reference.text.trim()}');
      }
    }
    for (final controller in [
      reference,
      issue,
      impact,
      rootCause,
      corrective,
      owner
    ]) {
      controller.dispose();
    }
  }

  Future<void> _offlineTransfer() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Wrap(children: [
        const ListTile(
            title: Text('Offline phone transfer'),
            subtitle: Text('No cloud or mobile data is required.')),
        ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Show supplier transfer QR'),
            onTap: () => Navigator.pop(context, 'export')),
        ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan supplier transfer QR'),
            onTap: () => Navigator.pop(context, 'import')),
      ])),
    );
    if (action == 'export') return _exportSupplierQr();
    if (action == 'import') return _importSupplierQr();
  }

  Future<void> _exportSupplierQr() async {
    final supplier = await _pickSupplier(title: 'Supplier to transfer');
    if (supplier == null) return;
    final contacts = await _db.getContacts(supplier.id!);
    final products = await _db.getProducts(supplier.id!);
    final code = _engine.encodeTransfer({
      'supplier': {
        'name': supplier.name,
        'booth': supplier.booth,
        'hall': supplier.hall,
        'category': supplier.category,
        'country': supplier.country,
        'notes': supplier.contactCompanyNotes,
      },
      'contacts': [
        for (final item in contacts.take(4))
          {
            'name': item.name,
            'role': item.designation,
            'phone': item.phone,
            'email': item.email,
            'whatsapp': item.whatsapp,
            'wechat': item.wechat
          }
      ],
      'products': [
        for (final item in products.take(6))
          {
            'name': item.name,
            'model': item.modelCode,
            'specs': item.specs,
            'moq': item.moq,
            'price': item.quotedPrice,
            'currency': item.priceCurrency
          }
      ],
    });
    if (!mounted) return;
    if (code.length > 2800) {
      _message(
          'This record is too large for a reliable QR. Reduce long notes or use cloud sync.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(
              data: code,
              size: 240,
              errorCorrectionLevel: QrErrorCorrectLevel.M),
          const SizedBox(height: 8),
          const Text(
              'The receiving phone should scan this from Offline phone transfer.'),
        ]),
        actions: [
          TextButton(
              onPressed: () => SharePlus.instance.share(ShareParams(
                  text: code, subject: 'Fair Expert supplier transfer')),
              child: const Text('Share code')),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _importSupplierQr() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code == null || !mounted) return;
    Map<String, dynamic> payload;
    try {
      payload = _engine.decodeTransfer(code);
    } catch (error) {
      _message(error.toString());
      return;
    }
    final supplierData =
        Map<String, dynamic>.from(payload['supplier'] as Map? ?? const {});
    final trip = await _pickTrip();
    if (trip == null) return;
    final name = supplierData['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      _message('The transferred supplier has no name.');
      return;
    }
    final duplicates = (await _db.getExhibitors(trip.id))
        .where((item) => item.name.trim().toLowerCase() == name.toLowerCase());
    if (duplicates.isNotEmpty) {
      _message(
          '$name already exists in this trip. Review duplicates before importing.');
      return;
    }
    final supplierId = await _db.insert(
        'exhibitors',
        Exhibitor(
          tripId: trip.id!,
          name: name,
          booth: supplierData['booth']?.toString() ?? '',
          hall: supplierData['hall']?.toString() ?? '',
          category: supplierData['category']?.toString() ?? '',
          country: supplierData['country']?.toString() ?? '',
          contactCompanyNotes: supplierData['notes']?.toString() ?? '',
        ).toMap()
          ..remove('id'));
    for (final raw in payload['contacts'] as List? ?? const []) {
      final item = Map<String, dynamic>.from(raw as Map);
      await _db.insert(
          'contacts',
          Contact(
                  exhibitorId: supplierId,
                  name: item['name']?.toString() ?? 'Contact',
                  designation: item['role']?.toString() ?? '',
                  phone: item['phone']?.toString() ?? '',
                  email: item['email']?.toString() ?? '',
                  whatsapp: item['whatsapp']?.toString() ?? '',
                  wechat: item['wechat']?.toString() ?? '')
              .toMap()
            ..remove('id'));
    }
    for (final raw in payload['products'] as List? ?? const []) {
      final item = Map<String, dynamic>.from(raw as Map);
      await _db.insert(
          'products',
          Product(
                  exhibitorId: supplierId,
                  name: item['name']?.toString() ?? 'Product',
                  modelCode: item['model']?.toString() ?? '',
                  specs: item['specs']?.toString() ?? '',
                  moq: (item['moq'] as num?)?.toDouble(),
                  quotedPrice: (item['price'] as num?)?.toDouble(),
                  priceCurrency: item['currency']?.toString() ?? 'USD')
              .toMap()
            ..remove('id'));
    }
    await _save(
        kind: 'offline_transfer',
        title: name,
        supplierId: supplierId,
        tripId: trip.id,
        status: 'Imported',
        data: {
          'contact_count': (payload['contacts'] as List? ?? const []).length,
          'product_count': (payload['products'] as List? ?? const []).length
        });
    _message('$name imported from the other phone.');
  }

  Future<void> _glossary() async {
    final records = (await _loadRecords())
        .where((row) => row['kind'] == 'fair_glossary')
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
          child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Text('Fair terminology glossary',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _addGlossaryTerm();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Term')),
              ])),
          const Divider(),
          Expanded(
              child: records.isEmpty
                  ? const EmptyState(
                      icon: Icons.translate_outlined,
                      title: 'No approved terms',
                      message:
                          'Add product, material, measurement and negotiation terms.')
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      for (final row in records)
                        Card(
                            child: ListTile(
                          title: Text(row['title'] as String),
                          subtitle: Text(
                              '${_data(row)['translation'] ?? ''}\n${_data(row)['context'] ?? ''}'),
                          isThreeLine: true,
                          trailing: IconButton(
                              tooltip: 'Copy translation',
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text:
                                        _data(row)['translation']?.toString() ??
                                            ''));
                                _message('Translation copied.');
                              }),
                        ))
                    ])),
        ]),
      )),
    );
  }

  Future<void> _addGlossaryTerm() async {
    final term = TextEditingController();
    final translation = TextEditingController();
    final language = TextEditingController(text: 'Chinese');
    final contextNote = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Add approved term'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: term,
                    decoration:
                        const InputDecoration(labelText: 'Source term')),
                const SizedBox(height: 10),
                TextField(
                    controller: translation,
                    decoration: const InputDecoration(
                        labelText: 'Approved translation')),
                const SizedBox(height: 10),
                TextField(
                    controller: language,
                    decoration: const InputDecoration(labelText: 'Language')),
                const SizedBox(height: 10),
                TextField(
                    controller: contextNote,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Meaning, unit or usage note')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save term'))
              ],
            ));
    if (save == true && term.text.trim().isNotEmpty) {
      await _save(
          kind: 'fair_glossary',
          title: term.text.trim(),
          status: 'Approved',
          data: {
            'translation': translation.text.trim(),
            'language': language.text.trim(),
            'context': contextNote.text.trim()
          });
    }
    term.dispose();
    translation.dispose();
    language.dispose();
    contextNote.dispose();
  }

  Future<void> _readiness() async {
    final root = await getApplicationDocumentsDirectory();
    var storageWritable = false;
    final probe = File(path.join(root.path, '.readiness_probe'));
    try {
      await probe.writeAsString('ok');
      await probe.delete();
      storageWritable = true;
    } catch (_) {
      storageWritable = false;
    }
    final attachments =
        (await _db.queryAll('attachments')).map(Attachment.fromMap).toList();
    final missingFiles =
        attachments.where((item) => !File(item.path).existsSync()).length;
    final reviewItems = (await _loadRecords())
        .where((row) =>
            row['status'] == 'Needs review' ||
            row['status'] == 'Needs attention')
        .length;
    final conflicts = (await _db.getCloudSyncConflicts()).length;
    final sync = await SyncStatusService().load();
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    final checks = <(String, String, bool)>[
      (
        'Signed-in session',
        signedIn ? 'Ready' : 'Sign in before team sync',
        signedIn
      ),
      (
        'Local storage',
        storageWritable ? 'Writable' : 'Storage is unavailable',
        storageWritable
      ),
      (
        'Attachment files',
        missingFiles == 0
            ? '${attachments.length} files available'
            : '$missingFiles local files missing',
        missingFiles == 0
      ),
      (
        'Review queue',
        reviewItems == 0 ? 'Clear' : '$reviewItems items need review',
        reviewItems == 0
      ),
      (
        'Sync conflicts',
        conflicts == 0 ? 'Clear' : '$conflicts conflicts need resolution',
        conflicts == 0
      ),
      (
        'Last cloud sync',
        sync.lastSyncedAt == null
            ? 'Never synchronized'
            : sync.lastSyncedAt!.toLocal().toString(),
        sync.lastSyncedAt != null && sync.lastError == null
      ),
      (
        'Camera readiness',
        'Open Scan card once before the fair to confirm permission',
        true
      ),
      (
        'Microphone readiness',
        'Open Meeting recorder once to confirm permission',
        true
      ),
      (
        'Offline translation',
        'Download English/Chinese models before travelling',
        true
      ),
      (
        'Power and backup',
        'Carry a power bank and create a fresh backup',
        true
      ),
    ];
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Field-readiness centre',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                    '${checks.where((item) => item.$3).length} of ${checks.length} checks ready'),
                const SizedBox(height: 12),
                for (final check in checks)
                  Card(
                      child: ListTile(
                          leading: Icon(
                              check.$3
                                  ? Icons.check_circle
                                  : Icons.warning_amber,
                              color:
                                  check.$3 ? AppColors.teal : AppColors.amber),
                          title: Text(check.$1),
                          subtitle: Text(check.$2))),
              ]),
            )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Intelligence & logistics')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _records,
          builder: (context, snapshot) {
            final records = snapshot.data ?? const <Map<String, dynamic>>[];
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('Field intelligence',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                  'Connect conversations, fair activity, logistics, compliance and post-order quality in one workspace.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 18),
              for (var index = 0; index < _tools.length; index++) ...[
                if (index == 0) const _SectionLabel('COMMUNICATE & DISCOVER'),
                if (index == 3) const _SectionLabel('COORDINATE AT THE FAIR'),
                if (index == 5) const _SectionLabel('COST, TRADE & COMPLIANCE'),
                if (index == 10) const _SectionLabel('DELIVERY & QUALITY'),
                if (index == 13) const _SectionLabel('FIELD SUPPORT'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_tools[index].icon,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                    ),
                    title: Text(_tools[index].title),
                    subtitle: Text(_tools[index].subtitle),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (records
                          .any((row) => row['kind'] == _tools[index].kind)) ...[
                        InfoChip(
                            label:
                                '${records.where((row) => row['kind'] == _tools[index].kind).length}'),
                        IconButton(
                          tooltip: 'View records',
                          icon: const Icon(Icons.history),
                          onPressed: () => _showHistory(_tools[index].kind),
                        ),
                      ],
                      const Icon(Icons.chevron_right),
                    ]),
                    onTap: () => _open(_tools[index]),
                  ),
                ),
              ],
            ]);
          },
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
}

class _ScoreSlider extends StatelessWidget {
  const _ScoreSlider(this.label, this.value, this.onChanged);
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(child: Text(label)),
          InfoChip(label: '${value.round()}/5'),
        ]),
        Slider(
            value: value,
            min: 1,
            max: 5,
            divisions: 4,
            label: '${value.round()}',
            onChanged: onChanged),
      ]);
}
