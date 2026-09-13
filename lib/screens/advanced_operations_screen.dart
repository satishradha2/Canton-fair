import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/business_card_parser.dart';
import '../data/database.dart';
import '../data/external_share_service.dart';
import '../data/phone_number_normalizer.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import 'ocr_screen.dart';

class AdvancedOperationsScreen extends StatefulWidget {
  const AdvancedOperationsScreen({super.key});

  @override
  State<AdvancedOperationsScreen> createState() =>
      _AdvancedOperationsScreenState();
}

class _Tool {
  const _Tool(this.kind, this.title, this.subtitle, this.icon);
  final String kind;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _AdvancedOperationsScreenState extends State<AdvancedOperationsScreen> {
  final _db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _items = _loadItems();

  static const _tools = <_Tool>[
    _Tool('supplier_request', 'Supplier information request',
        'Secure link for missing details, documents and quotes', Icons.link),
    _Tool('rfq_response', 'RFQ response comparison',
        'Compare supplier bids against one request', Icons.compare_arrows),
    _Tool('batch_card', 'Batch card inbox',
        'Photograph many cards and review them later', Icons.style_outlined),
    _Tool(
        'document_import',
        'Document extraction',
        'Read quote, catalogue and certificate images',
        Icons.document_scanner_outlined),
    _Tool(
        'completion_review',
        'Data completion centre',
        'Find missing, uncertain and expired information',
        Icons.fact_check_outlined),
    _Tool(
        'capture_template',
        'Capture templates',
        'Reusable required fields for each product category',
        Icons.dynamic_form_outlined),
    _Tool(
        'followup_sequence',
        'Follow-up sequences',
        'Create a scheduled multi-step supplier cadence',
        Icons.account_tree_outlined),
    _Tool(
        'response_event',
        'Supplier response tracking',
        'Record replies, response time and completeness',
        Icons.mark_email_read_outlined),
    _Tool(
        'product_variant',
        'Product variant matrix',
        'Structured models, colours, sizes and price breaks',
        Icons.view_comfy_alt_outlined),
    _Tool(
        'supplier_watchlist',
        'Shared supplier watchlist',
        'Visible team warnings and do-not-engage reasons',
        Icons.gpp_maybe_outlined),
    _Tool(
        'negotiation',
        'Negotiation workspace',
        'Targets, counteroffers, concessions and final position',
        Icons.handshake_outlined),
    _Tool(
        'trip_budget',
        'Budget controls',
        'Trip limits, actual expenses and remaining budget',
        Icons.account_balance_wallet_outlined),
    _Tool(
        'quick_capture',
        'Home-screen quick capture',
        'One tap to scan a card or capture an operational note',
        Icons.flash_on_outlined),
    _Tool(
        'duplicate_review',
        'Contact and company duplicates',
        'Review matching phones, emails and company identities',
        Icons.merge_type_outlined),
    _Tool(
        'management_share',
        'Secure management sharing',
        'Expiring read-only supplier and shortlist links',
        Icons.admin_panel_settings_outlined),
  ];

  Future<List<Map<String, dynamic>>> _loadItems() =>
      _db.queryAll('workflow_items', orderBy: 'updated_at DESC');

  void _refresh() => setState(() => _items = _loadItems());

  Future<Exhibitor?> _pickSupplier() async {
    final suppliers = await _db.getExhibitors(null);
    if (!mounted) return null;
    return showModalBottomSheet<Exhibitor>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose supplier')),
            for (final supplier in suppliers)
              ListTile(
                title: Text(supplier.name),
                subtitle: Text([supplier.booth, supplier.country]
                    .where((value) => value.isNotEmpty)
                    .join(' | ')),
                onTap: () => Navigator.pop(context, supplier),
              ),
          ],
        ),
      ),
    );
  }

  Future<Trip?> _pickTrip() async {
    final trips = await _db.getTrips();
    if (!mounted || trips.isEmpty) return null;
    return showModalBottomSheet<Trip>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose trip')),
            for (final trip in trips)
              ListTile(
                title: Text(trip.name),
                subtitle: Text(trip.city),
                onTap: () => Navigator.pop(context, trip),
              ),
          ],
        ),
      ),
    );
  }

  Future<Product?> _pickProduct([int? supplierId]) async {
    final rows = await _db.queryAll('products',
        where: supplierId == null ? null : 'exhibitor_id = ?',
        whereArgs: supplierId == null ? null : [supplierId],
        orderBy: 'name');
    if (!mounted) return null;
    return showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose product')),
            for (final row in rows)
              ListTile(
                title: Text(row['name'] as String),
                subtitle: Text(row['model_code'] as String? ?? ''),
                onTap: () => Navigator.pop(context, Product.fromMap(row)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWorkflow({
    required String kind,
    required String title,
    required Map<String, Object?> data,
    String status = 'Open',
    int? tripId,
    int? supplierId,
    int? productId,
    int? contactId,
    DateTime? dueAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.insert('workflow_items', {
      'kind': kind,
      'trip_id': tripId,
      'exhibitor_id': supplierId,
      'product_id': productId,
      'contact_id': contactId,
      'title': title,
      'status': status,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'data_json': jsonEncode(data),
      'created_at': now,
      'updated_at': now,
    });
    await _db.logAudit('Created ${_titleFor(kind)}', title);
    _refresh();
  }

  String _titleFor(String kind) =>
      _tools.where((tool) => tool.kind == kind).firstOrNull?.title ?? kind;

  Future<void> _openTool(_Tool tool) async {
    switch (tool.kind) {
      case 'batch_card':
        return _batchCards();
      case 'document_import':
        return _extractDocument();
      case 'completion_review':
        return _completionCentre();
      case 'duplicate_review':
        return _duplicateCentre();
      case 'trip_budget':
        return _budgetCentre();
      case 'quick_capture':
        return _quickCapture();
      case 'supplier_request':
      case 'management_share':
        return _externalShare(tool.kind);
      case 'rfq_response':
        return _rfqResponseCentre(tool);
      case 'product_variant':
        return _variantCentre(tool);
      case 'followup_sequence':
        return _followupSequence();
      default:
        return _structuredEntry(tool);
    }
  }

  Map<String, String> _fieldsFor(String kind) => switch (kind) {
        'rfq_response' => {
            'rfq': 'RFQ title or reference',
            'unit_price': 'Unit price',
            'currency': 'Currency',
            'moq': 'MOQ',
            'lead_time': 'Lead time',
            'payment_terms': 'Payment terms',
            'tooling': 'Tooling cost',
            'packaging': 'Packaging',
            'valid_until': 'Validity date',
          },
        'capture_template' => {
            'category': 'Product category',
            'required_fields': 'Required fields (one per line)',
            'compliance_questions': 'Compliance questions (one per line)',
          },
        'response_event' => {
            'channel': 'Channel',
            'request_sent': 'Request sent date/time',
            'reply_received': 'Reply received date/time',
            'completeness': 'Response completeness (0-100)',
            'promised_date': 'Promised delivery date',
            'notes': 'Response notes',
          },
        'product_variant' => {
            'sku': 'SKU / model',
            'colour': 'Colour',
            'size': 'Size',
            'material': 'Material',
            'packaging': 'Packaging',
            'moq': 'MOQ',
            'unit_price': 'Unit price',
            'currency': 'Currency',
          },
        'supplier_watchlist' => {
            'severity': 'Severity',
            'category': 'Warning category',
            'reason': 'Reason and evidence',
            'review_owner': 'Review owner',
          },
        'negotiation' => {
            'target_price': 'Target price',
            'walk_away_price': 'Walk-away price',
            'target_moq': 'Acceptable MOQ',
            'incoterm': 'Preferred Incoterm',
            'supplier_offer': 'Supplier counteroffer',
            'our_concessions': 'Our concessions',
            'final_position': 'Final position',
          },
        _ => const {},
      };

  Future<void> _structuredEntry(_Tool tool) async {
    final isTemplate = tool.kind == 'capture_template';
    final supplier = isTemplate ? null : await _pickSupplier();
    if (!mounted || (!isTemplate && supplier == null)) return;
    Product? product;
    if (tool.kind == 'product_variant') {
      product = await _pickProduct(supplier!.id);
    }
    if (!mounted || (tool.kind == 'product_variant' && product == null)) return;
    final controllers = {
      for (final entry in _fieldsFor(tool.kind).entries)
        entry.key: TextEditingController(),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tool.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: InfoChip(
                      label: supplier?.name ?? 'Reusable team template',
                      icon: supplier == null
                          ? Icons.groups_outlined
                          : Icons.storefront_outlined)),
              const SizedBox(height: 12),
              for (final entry in _fieldsFor(tool.kind).entries) ...[
                TextField(
                  controller: controllers[entry.key],
                  minLines: entry.key.contains('notes') ||
                          entry.key.contains('fields') ||
                          entry.key.contains('questions') ||
                          entry.key.contains('reason') ||
                          entry.key.contains('position')
                      ? 2
                      : 1,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: entry.value),
                ),
                const SizedBox(height: 10),
              ],
            ]),
          ),
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
    );
    if (saved == true) {
      final data = {
        for (final entry in controllers.entries)
          entry.key: entry.value.text.trim()
      };
      if (tool.kind == 'response_event') {
        final sent = DateTime.tryParse(data['request_sent'] ?? '');
        final received = DateTime.tryParse(data['reply_received'] ?? '');
        if (sent != null && received != null && !received.isBefore(sent)) {
          data['response_hours'] =
              (received.difference(sent).inMinutes / 60).toStringAsFixed(1);
        }
      }
      await _saveWorkflow(
          kind: tool.kind,
          title: product == null
              ? supplier?.name ?? data['category'] ?? 'Capture template'
              : '${supplier!.name} - ${product.name}',
          supplierId: supplier?.id,
          productId: product?.id,
          data: data);
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _batchCards() async {
    final images = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (images.isEmpty) return;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(path.join(root.path, 'batch_cards'));
    await folder.create(recursive: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    var saved = 0;
    try {
      for (final image in images) {
        final destination = path.join(folder.path,
            '${DateTime.now().microsecondsSinceEpoch}_$saved${path.extension(image.path)}');
        await File(image.path).copy(destination);
        final text = (await recognizer
                .processImage(InputImage.fromFilePath(destination)))
            .text;
        final candidates = BusinessCardParser.candidates(text);
        final country = candidates['country']?.firstOrNull ?? '';
        final phones = (candidates['phone'] ?? const <String>[])
            .map((value) =>
                PhoneNumberNormalizer.normalize(value, country: country))
            .toList();
        await _saveWorkflow(
            kind: 'batch_card',
            title: candidates['name']?.firstOrNull ?? 'Card awaiting review',
            status: 'Needs review',
            data: {
              'image_path': destination,
              'raw_text': text,
              'candidates': candidates,
              'phones': phones,
            });
        saved++;
      }
    } finally {
      await recognizer.close();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$saved cards added to the review inbox.')));
    }
  }

  Future<void> _extractDocument() async {
    final supplier = await _pickSupplier();
    if (!mounted || supplier == null) return;
    final image = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (image == null) return;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(path.join(root.path, 'document_imports'));
    await folder.create(recursive: true);
    final sourcePath = path.join(folder.path,
        '${DateTime.now().microsecondsSinceEpoch}${path.extension(image.path)}');
    await File(image.path).copy(sourcePath);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text =
          (await recognizer.processImage(InputImage.fromFilePath(sourcePath)))
              .text;
      final prices = RegExp(r'(?:USD|CNY|RMB|EUR|AED|\$|¥|€)\s*\d+(?:[.,]\d+)?',
              caseSensitive: false)
          .allMatches(text)
          .map((match) => match.group(0)!)
          .toSet()
          .toList();
      final emails =
          BusinessCardParser.candidates(text)['email'] ?? const <String>[];
      await _saveWorkflow(
          kind: 'document_import',
          title: supplier.name,
          supplierId: supplier.id,
          status: 'Needs review',
          data: {
            'document_text': text,
            'price_candidates': prices,
            'email_candidates': emails,
            'source_path': sourcePath,
          });
      if (mounted) {
        _showMessage('Document extracted into the review queue.');
      }
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _completionCentre() async {
    final suppliers = await _db.getExhibitors(null);
    final contacts =
        (await _db.queryAll('contacts')).map(Contact.fromMap).toList();
    final products =
        (await _db.queryAll('products')).map(Product.fromMap).toList();
    final pendingReviews = (await _loadItems()).where((row) =>
        row['status'] == 'Needs review' || row['status'] == 'Needs attention');
    final issues = <String>[];
    for (final supplier in suppliers) {
      final missing = <String>[
        if (supplier.booth.isEmpty) 'booth',
        if (supplier.country.isEmpty) 'country',
        if (!contacts.any((c) => c.exhibitorId == supplier.id)) 'contact',
        if (!products.any((p) => p.exhibitorId == supplier.id)) 'product',
      ];
      if (missing.isNotEmpty) {
        issues.add('${supplier.name}: ${missing.join(', ')}');
      }
      try {
        final verification = Map<String, dynamic>.from(
            jsonDecode(supplier.verificationJson) as Map);
        for (final raw in verification['certificates'] as List? ?? const []) {
          final certificate = Map<String, dynamic>.from(raw as Map);
          final expiry =
              DateTime.tryParse(certificate['expiry']?.toString() ?? '');
          if (certificate['verified'] != true) {
            issues.add(
                '${supplier.name}: ${certificate['type'] ?? 'certificate'} not verified');
          } else if (expiry != null &&
              expiry.isBefore(DateTime.now().add(const Duration(days: 60)))) {
            issues.add(
                '${supplier.name}: ${certificate['type'] ?? 'certificate'} expires ${expiry.toLocal().toString().split(' ').first}');
          }
        }
      } catch (_) {
        issues.add('${supplier.name}: verification data needs review');
      }
    }
    for (final row in pendingReviews) {
      issues.add(
          '${_titleFor(row['kind'] as String)}: ${row['title']} needs review');
    }
    await _showLines('Data completion centre', issues,
        empty: 'All supplier essentials are complete.');
  }

  Future<void> _duplicateCentre() async {
    final contacts =
        (await _db.queryAll('contacts')).map(Contact.fromMap).toList();
    final groups = <String, List<Contact>>{};
    for (final contact in contacts) {
      for (final identity in [
        contact.email.trim().toLowerCase(),
        contact.phone.replaceAll(RegExp(r'\D'), '')
      ].where((value) => value.isNotEmpty)) {
        groups.putIfAbsent(identity, () => []).add(contact);
      }
    }
    final lines = groups.entries
        .where((entry) =>
            entry.value.map((contact) => contact.exhibitorId).toSet().length >
            1)
        .map((entry) =>
            '${entry.key}: ${entry.value.map((c) => c.name).toSet().join(', ')}')
        .toList();
    final suppliers = await _db.getExhibitors(null);
    final companies = <String, List<Exhibitor>>{};
    for (final supplier in suppliers) {
      final profile = supplier.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .replaceAll(RegExp(r'(limited|ltd|llc|inc|company|co)$'), '');
      if (profile.isNotEmpty) {
        companies.putIfAbsent(profile, () => []).add(supplier);
      }
    }
    lines.addAll(companies.entries.where((entry) => entry.value.length > 1).map(
        (entry) =>
            'Company match: ${entry.value.map((s) => s.name).join(' / ')}'));
    await _showLines('Possible contact and company duplicates', lines,
        empty: 'No cross-supplier phone or email matches found.');
  }

  Future<void> _followupSequence() async {
    final supplier = await _pickSupplier();
    if (!mounted || supplier == null) return;
    final steps = [
      ('Thank-you message', 1),
      ('Request quotation', 3),
      ('Quotation reminder', 7),
      ('Final escalation', 14),
    ];
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Create follow-up sequence'),
              content: Text(
                  '${supplier.name}\n\n${steps.map((s) => 'Day ${s.$2}: ${s.$1}').join('\n')}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Create 4 tasks'))
              ],
            ));
    if (confirmed != true) return;
    for (final step in steps) {
      await _db.insert(
          'meetings',
          Meeting(
                  exhibitorId: supplier.id!,
                  meetingDate: DateTime.now(),
                  followUpDate: DateTime.now().add(Duration(days: step.$2)),
                  outcome: step.$1,
                  priority: step.$2 <= 3 ? 'High' : 'Medium')
              .toMap()
            ..remove('id'));
    }
    await _saveWorkflow(
        kind: 'followup_sequence',
        title: supplier.name,
        supplierId: supplier.id,
        status: 'Active',
        data: {
          'steps': [
            for (final step in steps) {'title': step.$1, 'day': step.$2}
          ],
        });
    if (mounted) _showMessage('Four dated follow-up tasks created.');
  }

  Map<String, dynamic> _workflowData(Map<String, dynamic> row) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(row['data_json'] as String? ?? '{}') as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _rfqResponseCentre(_Tool tool) async {
    final records = (await _loadItems())
        .where((row) => row['kind'] == 'rfq_response')
        .toList();
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Expanded(
                    child: Text('RFQ response comparison',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _structuredEntry(tool);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Response')),
              ]),
            ),
            Expanded(
              child: records.isEmpty
                  ? const EmptyState(
                      icon: Icons.compare_arrows,
                      title: 'No supplier responses',
                      message: 'Add responses to compare price, MOQ and terms.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final group in _groupByReference(records).entries)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(group.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(columns: const [
                                      DataColumn(label: Text('Supplier')),
                                      DataColumn(label: Text('Price')),
                                      DataColumn(label: Text('MOQ')),
                                      DataColumn(label: Text('Lead time')),
                                      DataColumn(label: Text('Payment')),
                                    ], rows: [
                                      for (final row in group.value)
                                        DataRow(cells: [
                                          DataCell(
                                              Text(row['title'] as String)),
                                          DataCell(Text(
                                              '${_workflowData(row)['unit_price'] ?? '-'} ${_workflowData(row)['currency'] ?? ''}')),
                                          DataCell(Text(
                                              _workflowData(row)['moq']
                                                      ?.toString() ??
                                                  '-')),
                                          DataCell(Text(
                                              _workflowData(row)['lead_time']
                                                      ?.toString() ??
                                                  '-')),
                                          DataCell(Text(_workflowData(
                                                      row)['payment_terms']
                                                  ?.toString() ??
                                              '-')),
                                        ])
                                    ]),
                                  ),
                                ],
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
    _refresh();
  }

  Map<String, List<Map<String, dynamic>>> _groupByReference(
      List<Map<String, dynamic>> records) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in records) {
      final reference = _workflowData(row)['rfq']?.toString().trim();
      groups
          .putIfAbsent(
              reference == null || reference.isEmpty
                  ? 'Unassigned RFQ'
                  : reference,
              () => [])
          .add(row);
    }
    return groups;
  }

  Future<void> _variantCentre(_Tool tool) async {
    final records = (await _loadItems())
        .where((row) => row['kind'] == 'product_variant')
        .toList();
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Expanded(
                    child: Text('Product variant matrix',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _structuredEntry(tool);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Variant')),
              ]),
            ),
            Expanded(
              child: records.isEmpty
                  ? const EmptyState(
                      icon: Icons.view_comfy_alt_outlined,
                      title: 'No variants',
                      message: 'Add models, sizes, colours and price breaks.')
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(columns: const [
                          DataColumn(label: Text('Product / supplier')),
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Colour')),
                          DataColumn(label: Text('Size')),
                          DataColumn(label: Text('Material')),
                          DataColumn(label: Text('MOQ')),
                          DataColumn(label: Text('Price')),
                        ], rows: [
                          for (final row in records)
                            DataRow(cells: [
                              DataCell(Text(row['title'] as String)),
                              DataCell(Text(
                                  _workflowData(row)['sku']?.toString() ??
                                      '-')),
                              DataCell(Text(
                                  _workflowData(row)['colour']?.toString() ??
                                      '-')),
                              DataCell(Text(
                                  _workflowData(row)['size']?.toString() ??
                                      '-')),
                              DataCell(Text(
                                  _workflowData(row)['material']?.toString() ??
                                      '-')),
                              DataCell(Text(
                                  _workflowData(row)['moq']?.toString() ??
                                      '-')),
                              DataCell(Text(
                                  '${_workflowData(row)['unit_price'] ?? '-'} ${_workflowData(row)['currency'] ?? ''}')),
                            ])
                        ]),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
    _refresh();
  }

  Future<void> _budgetCentre() async {
    final trips = await _db.getTrips();
    final budgets = (await _loadItems())
        .where((row) => row['kind'] == 'trip_budget')
        .toList();
    final expenses = await _db.queryAll('expenses');
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(
                      child: Text('Trip budgets',
                          style: Theme.of(context).textTheme.titleLarge)),
                  FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _addBudget(trips);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Budget'))
                ]),
                const SizedBox(height: 16),
                for (final trip in trips)
                  Builder(builder: (context) {
                    final budgetRow = budgets
                        .where((row) => row['trip_id'] == trip.id)
                        .firstOrNull;
                    final data = budgetRow == null
                        ? const <String, dynamic>{}
                        : Map<String, dynamic>.from(
                            jsonDecode(budgetRow['data_json'] as String)
                                as Map);
                    final limit =
                        double.tryParse(data['limit']?.toString() ?? '') ?? 0;
                    final budgetCurrency =
                        data['currency']?.toString().toUpperCase() ?? 'CNY';
                    final tripExpenses =
                        expenses.where((row) => row['trip_id'] == trip.id);
                    final spent = expenses
                        .where((row) =>
                            row['trip_id'] == trip.id &&
                            row['currency']?.toString().toUpperCase() ==
                                budgetCurrency)
                        .fold<double>(
                            0,
                            (sum, row) =>
                                sum +
                                ((row['amount'] as num?)?.toDouble() ?? 0));
                    final otherCurrencies = tripExpenses
                        .map((row) => row['currency']?.toString().toUpperCase())
                        .whereType<String>()
                        .where((value) => value != budgetCurrency)
                        .toSet();
                    return Card(
                        child: ListTile(
                            title: Text(trip.name),
                            subtitle: Text([
                              'Spent ${spent.toStringAsFixed(2)} $budgetCurrency | Remaining ${(limit - spent).toStringAsFixed(2)}',
                              if (otherCurrencies.isNotEmpty)
                                'Not converted: ${otherCurrencies.join(', ')}'
                            ].join('\n')),
                            trailing: InfoChip(
                                label: limit == 0
                                    ? 'No limit'
                                    : '${(spent / limit * 100).clamp(0, 999).round()}%',
                                color: limit > 0 && spent > limit
                                    ? AppColors.danger
                                    : AppColors.teal)));
                  }),
              ]),
            )));
  }

  Future<void> _addBudget(List<Trip> trips) async {
    if (trips.isEmpty) return _showMessage('Create a trip first.');
    Trip trip = trips.first;
    final limit = TextEditingController();
    final currency = TextEditingController(text: 'CNY');
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Set trip budget'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<Trip>(
                    initialValue: trip,
                    items: trips
                        .map((item) => DropdownMenuItem(
                            value: item, child: Text(item.name)))
                        .toList(),
                    onChanged: (value) => trip = value ?? trip,
                    decoration: const InputDecoration(labelText: 'Trip')),
                TextField(
                    controller: limit,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Budget limit')),
                TextField(
                    controller: currency,
                    decoration: const InputDecoration(labelText: 'Currency')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save'))
              ],
            ));
    if (save == true) {
      await _saveWorkflow(
          kind: 'trip_budget',
          title: trip.name,
          tripId: trip.id,
          data: {'limit': limit.text.trim(), 'currency': currency.text.trim()});
    }
    limit.dispose();
    currency.dispose();
  }

  Future<void> _externalShare(String kind) async {
    if (kind == 'supplier_request') {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Wrap(children: [
            const ListTile(
                title: Text('Supplier information requests'),
                subtitle: Text('Create a secure request or collect replies.')),
            ListTile(
                leading: const Icon(Icons.add_link),
                title: const Text('Create request link'),
                onTap: () => Navigator.pop(context, 'create')),
            ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Collect supplier responses'),
                onTap: () => Navigator.pop(context, 'responses')),
          ]),
        ),
      );
      if (action == 'responses') return _collectSupplierResponses();
      if (action != 'create') return;
    }
    final supplier = await _pickSupplier();
    if (!mounted || supplier == null) return;
    final mode = kind == 'supplier_request' ? 'supplier_request' : 'read_only';
    try {
      final contacts = await _db.getContacts(supplier.id!);
      final products = await _db.getProducts(supplier.id!);
      final productSummaries = <Map<String, Object?>>[];
      for (final product in products) {
        final quotes = await _db.getQuotes(product.id!);
        final latest = quotes.firstOrNull;
        productSummaries.add({
          'name': product.name,
          'model': product.modelCode,
          'moq': latest?.moq ?? product.moq,
          'price': latest?.unitPrice ?? product.quotedPrice,
          'currency': latest?.currency ?? product.priceCurrency,
          'lead_time': product.leadTime,
        });
      }
      final uri = await const ExternalShareService().create(
          mode: mode,
          title: supplier.name,
          validity: const Duration(days: 7),
          payload: {
            'supplier_id': supplier.id,
            'supplier_name': supplier.name,
            'booth': supplier.booth,
            'country': supplier.country,
            'category': supplier.category,
            'decision': supplier.decision,
            'score': supplier.decisionScore,
            'contacts': [
              for (final contact in contacts)
                {
                  'name': contact.name,
                  'role': contact.designation,
                  'phone': contact.phone,
                  'email': contact.email,
                }
            ],
            'products': productSummaries,
            if (mode == 'supplier_request')
              'requested_fields': [
                'company profile',
                'contacts',
                'quotation',
                'certificates',
                'catalogue'
              ],
          });
      await _saveWorkflow(
          kind: kind,
          title: supplier.name,
          supplierId: supplier.id,
          status: 'Shared',
          dueAt: DateTime.now().add(const Duration(days: 7)),
          data: {'url': uri.toString(), 'mode': mode});
      await SharePlus.instance.share(ShareParams(
          text:
              '${mode == 'supplier_request' ? 'Please complete the requested supplier information' : 'View supplier summary'}:\n$uri'));
    } catch (error) {
      if (mounted) {
        _showMessage(error is StateError
            ? error.message.toString()
            : 'Could not create secure link.');
      }
    }
  }

  Future<void> _collectSupplierResponses() async {
    try {
      final responses = await const ExternalShareService().responses();
      final existing = await _loadItems();
      final imported = existing
          .where((row) => row['kind'] == 'response_event')
          .map(_workflowData)
          .map((data) => data['external_share_id']?.toString())
          .whereType<String>()
          .toSet();
      var count = 0;
      for (final response in responses) {
        final id = response['id']?.toString() ?? '';
        if (id.isEmpty || imported.contains(id)) continue;
        await _saveWorkflow(
          kind: 'response_event',
          title: response['title']?.toString() ?? 'Supplier response',
          status: 'Needs review',
          data: {
            'external_share_id': id,
            'reply_received': response['responded_at'],
            'channel': 'Secure supplier link',
            'response': response['response'],
          },
        );
        count++;
      }
      if (mounted) {
        _showMessage(count == 0
            ? 'No new supplier responses.'
            : '$count supplier response${count == 1 ? '' : 's'} added for review.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error is StateError
            ? error.message.toString()
            : 'Could not collect supplier responses.');
      }
    }
  }

  Future<void> _quickCapture() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OcrScreen()));
    _refresh();
  }

  Future<void> _showLines(String title, List<String> lines,
          {required String empty}) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => SafeArea(
                  child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .72,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  if (lines.isEmpty)
                    EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Nothing needs attention',
                        message: empty)
                  else
                    for (final line in lines)
                      Card(
                          child: ListTile(
                              leading: const Icon(Icons.warning_amber_outlined),
                              title: Text(line))),
                ]),
              )));

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _showRegister(String kind) async {
    final items =
        (await _loadItems()).where((row) => row['kind'] == kind).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(_titleFor(kind),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No records yet',
                      message:
                          'Use the add action to create the first record.'),
                for (final item in items)
                  Card(
                      child: ExpansionTile(
                    title: Text(item['title'] as String),
                    subtitle: Text(item['status'] as String),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                              const JsonEncoder.withIndent('  ').convert(
                                  jsonDecode(item['data_json'] as String)))),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          if (kind == 'batch_card' &&
                              item['status'] != 'Completed')
                            FilledButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _createSupplierFromCard(item);
                              },
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('Create supplier'),
                            ),
                          if (kind == 'document_import' &&
                              item['status'] != 'Completed')
                            FilledButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _createQuoteFromDocument(item);
                              },
                              icon: const Icon(Icons.request_quote_outlined),
                              label: const Text('Create quote'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _db
                                  .update('workflow_items', item['id'] as int, {
                                'status': item['status'] == 'Completed'
                                    ? 'Open'
                                    : 'Completed',
                                'updated_at':
                                    DateTime.now().toUtc().toIso8601String(),
                              });
                              if (context.mounted) Navigator.pop(context);
                              _refresh();
                            },
                            icon: Icon(item['status'] == 'Completed'
                                ? Icons.undo
                                : Icons.check),
                            label: Text(item['status'] == 'Completed'
                                ? 'Reopen'
                                : 'Complete'),
                          ),
                        ]),
                      ),
                    ],
                  )),
              ]),
            )));
  }

  Future<void> _createSupplierFromCard(Map<String, dynamic> item) async {
    final trip = await _pickTrip();
    if (trip == null || !mounted) return;
    final data = _workflowData(item);
    final rawCandidates = data['candidates'] as Map? ?? const {};
    final candidates = <String, List<String>>{
      for (final entry in rawCandidates.entries)
        entry.key.toString():
            (entry.value as List? ?? const []).map((e) => e.toString()).toList()
    };
    String first(String key) => candidates[key]?.firstOrNull ?? '';
    final company =
        first('name').isEmpty ? item['title'] as String : first('name');
    final existing = (await _db.getExhibitors(trip.id)).where((supplier) =>
        supplier.name.trim().toLowerCase() == company.trim().toLowerCase());
    if (existing.isNotEmpty) {
      _showMessage('A supplier named $company already exists in this trip.');
      return;
    }
    final normalizedPhones = (data['phones'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final supplierId = await _db.insert(
        'exhibitors',
        Exhibitor(
          tripId: trip.id!,
          name: company.isEmpty ? 'Card supplier' : company,
          booth: first('booth'),
          hall: first('hall'),
          category: '',
          country: first('country'),
          fieldCaptureJson: jsonEncode({
            'supplier_details': {
              'name': company,
              'websites': (candidates['websites'] ?? const []).join('\n'),
              'address': (candidates['address'] ?? const []).join('\n'),
              'companyEmails': (candidates['email'] ?? const []).join('\n'),
              'companyPhones': normalizedPhones.join('\n'),
            },
            'batch_card_source': item['id'],
          }),
        ).toMap()
          ..remove('id'));
    final emails = candidates['email'] ?? const <String>[];
    await _db.insert(
        'contacts',
        Contact(
          exhibitorId: supplierId,
          name: first('person').isEmpty ? 'Card contact' : first('person'),
          designation: first('role'),
          phone: normalizedPhones.firstOrNull ?? '',
          email: emails.firstOrNull ?? '',
          profileJson: jsonEncode({
            'details': {
              'otherPhones': normalizedPhones.skip(1).join('\n'),
              'otherEmails': emails.skip(1).join('\n'),
            }
          }),
        ).toMap()
          ..remove('id'));
    final imagePath = data['image_path']?.toString() ?? '';
    if (imagePath.isNotEmpty && await File(imagePath).exists()) {
      await _db.insert(
          'attachments',
          Attachment(
                  ownerType: 'exhibitor',
                  ownerId: supplierId,
                  kind: 'image',
                  path: imagePath,
                  note: 'Batch business card',
                  createdAt: DateTime.now())
              .toMap()
            ..remove('id'));
    }
    await _db.update('workflow_items', item['id'] as int, {
      'status': 'Completed',
      'exhibitor_id': supplierId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _refresh();
    _showMessage('Supplier and contact created from the reviewed card.');
  }

  Future<void> _createQuoteFromDocument(Map<String, dynamic> item) async {
    final supplierId = item['exhibitor_id'] as int?;
    final product = await _pickProduct(supplierId);
    if (product == null || !mounted) return;
    final data = _workflowData(item);
    final firstPrice = (data['price_candidates'] as List? ?? const [])
        .map((value) => value.toString())
        .firstOrNull;
    final amount = TextEditingController(
        text: firstPrice == null
            ? ''
            : RegExp(r'\d+(?:[.,]\d+)?')
                    .firstMatch(firstPrice)
                    ?.group(0)
                    ?.replaceAll(',', '.') ??
                '');
    final currency = TextEditingController(
        text: firstPrice?.toUpperCase().contains('CNY') == true ||
                firstPrice?.contains('¥') == true
            ? 'CNY'
            : firstPrice?.toUpperCase().contains('EUR') == true ||
                    firstPrice?.contains('€') == true
                ? 'EUR'
                : 'USD');
    final moq = TextEditingController();
    final label = TextEditingController(text: 'Extracted document quote');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review extracted quote'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Quote label')),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Unit price')),
            TextField(
                controller: currency,
                decoration: const InputDecoration(labelText: 'Currency')),
            TextField(
                controller: moq,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'MOQ')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create quote')),
        ],
      ),
    );
    if (save == true) {
      await _db.insert(
          'quotes',
          Quote(
            productId: product.id!,
            label: label.text.trim(),
            unitPrice: double.tryParse(amount.text.trim()),
            currency: currency.text.trim().toUpperCase(),
            moq: double.tryParse(moq.text.trim()),
            note: 'Created from document extraction review',
          ).toMap()
            ..remove('id'));
      final sourcePath = data['source_path']?.toString() ?? '';
      if (sourcePath.isNotEmpty && await File(sourcePath).exists()) {
        await _db.insert(
            'attachments',
            Attachment(
                    ownerType: 'product',
                    ownerId: product.id!,
                    kind: 'document',
                    path: sourcePath,
                    note: 'Source quotation document',
                    createdAt: DateTime.now())
                .toMap()
              ..remove('id'));
      }
      await _db.update('workflow_items', item['id'] as int, {
        'status': 'Completed',
        'product_id': product.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _refresh();
      _showMessage('Quote created after review.');
    }
    amount.dispose();
    currency.dispose();
    moq.dispose();
    label.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Advanced sourcing tools')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _items,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Map<String, dynamic>>[];
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text('Post-fair operations',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                    'Capture less manually, close information gaps, and move shortlisted suppliers toward a buying decision.',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 18),
                for (var index = 0; index < _tools.length; index++) ...[
                  if (index == 0) const _GroupLabel('COLLECT & COMPLETE'),
                  if (index == 5) const _GroupLabel('STANDARDIZE & FOLLOW UP'),
                  if (index == 9) const _GroupLabel('CONTROL & DECIDE'),
                  Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(_tools[index].icon,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer)),
                        title: Text(_tools[index].title),
                        subtitle: Text(_tools[index].subtitle),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (items
                              .where((row) => row['kind'] == _tools[index].kind)
                              .isNotEmpty)
                            InfoChip(
                                label:
                                    '${items.where((row) => row['kind'] == _tools[index].kind).length}'),
                          IconButton(
                              tooltip: 'View records',
                              icon: const Icon(Icons.history),
                              onPressed: () =>
                                  _showRegister(_tools[index].kind)),
                          const Icon(Icons.chevron_right),
                        ]),
                        onTap: () => _openTool(_tools[index]),
                      )),
                ],
              ]);
            }),
      );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
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
