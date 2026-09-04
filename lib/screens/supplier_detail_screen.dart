import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Exhibitor supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  final _db = TradeDatabase.instance;
  late String _decision;
  late String _verificationJson;
  late String _fieldCaptureJson;
  late Future<List<Contact>> _contacts;
  late Future<List<Product>> _products;
  late Future<List<Meeting>> _meetings;
  late Future<List<Attachment>> _files;
  late Future<List<Sample>> _samples;

  @override
  void initState() {
    super.initState();
    _decision = widget.supplier.decision;
    _verificationJson = widget.supplier.verificationJson;
    _fieldCaptureJson = widget.supplier.fieldCaptureJson;
    _reload();
  }

  Future<void> _setDecision(String decision) async {
    var reason = '';
    if (decision == 'Reject') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Why reject this supplier?'),
              content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Reason')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Save')),
              ],
            ),
          ) ??
          '';
      controller.dispose();
      if (reason.isEmpty) return;
    }
    await _db.update('exhibitors', widget.supplier.id!, {
      'decision': decision,
      'decision_reason': reason,
      'shortlisted': decision == 'Shortlist' ? 1 : 0,
    });
    if (mounted) setState(() => _decision = decision);
  }

  void _reload() {
    final id = widget.supplier.id!;
    _contacts = _db.getContacts(id);
    _products = _db.getProducts(id);
    _meetings = _db.getMeetings(exhibitorId: id);
    _files = _db.getAttachments('exhibitor', id);
    _samples = _db.getSamples(exhibitorId: id);
  }

  Future<void> _shareSummary() async {
    final supplier = widget.supplier;
    final products = await _products;
    final lines = [
      supplier.name,
      if (supplier.booth.isNotEmpty) 'Booth: ${supplier.booth}',
      if (supplier.hall.isNotEmpty) 'Hall: ${supplier.hall}',
      if (supplier.category.isNotEmpty) 'Category: ${supplier.category}',
      if (supplier.country.isNotEmpty) 'Country: ${supplier.country}',
      'Status: ${supplier.visitedAt == null ? 'Need to visit' : 'Visited'}',
      'Rating: ${supplier.rating}/5',
      if (products.isNotEmpty)
        'Products: ${products.map((item) => item.name).join(', ')}',
      if (supplier.contactCompanyNotes.isNotEmpty)
        'Notes: ${supplier.contactCompanyNotes}',
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  Future<void> _openPhone(String phone, {bool whatsapp = false}) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = whatsapp
        ? Uri.parse('https://wa.me/${clean.replaceFirst('+', '')}')
        : Uri.parse('tel:$clean');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $phone')),
      );
    }
  }

  Future<void> _complete(Meeting meeting) async {
    await _db.update('meetings', meeting.id!, {'completed': 1});
    await ReminderService.cancel(meeting.id!);
    if (mounted) setState(_reload);
  }

  Future<void> _openSampleDialog([Sample? sample]) async {
    final products = await _products;
    if (!mounted) return;
    var productId = sample?.productId;
    var requestedAt = sample?.requestedAt.toLocal() ?? DateTime.now();
    var expectedAt = sample?.expectedAt?.toLocal();
    var receivedAt = sample?.receivedAt?.toLocal();
    var status = sample?.status ?? 'Requested';
    final courier = TextEditingController(text: sample?.courier ?? '');
    final tracking = TextEditingController(text: sample?.trackingNumber ?? '');
    final sampleCost =
        TextEditingController(text: sample?.sampleCost?.toString() ?? '');
    final shippingCost =
        TextEditingController(text: sample?.shippingCost?.toString() ?? '');
    final assignee = TextEditingController(text: sample?.assigneeEmail ?? '');
    final notes = TextEditingController(text: sample?.testNotes ?? '');
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(sample == null ? 'Track sample' : 'Update sample'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int?>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Supplier-level sample')),
                    ...products.map((product) => DropdownMenuItem<int?>(
                        value: product.id, child: Text(product.name))),
                  ],
                  onChanged: (value) => setDialogState(() => productId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Sample status'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Requested', child: Text('Requested')),
                    DropdownMenuItem(value: 'Quoted', child: Text('Quoted')),
                    DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                    DropdownMenuItem(value: 'Shipped', child: Text('Shipped')),
                    DropdownMenuItem(
                        value: 'In transit', child: Text('In transit')),
                    DropdownMenuItem(
                        value: 'Received', child: Text('Received')),
                    DropdownMenuItem(value: 'Testing', child: Text('Testing')),
                    DropdownMenuItem(
                        value: 'Approved', child: Text('Approved')),
                    DropdownMenuItem(
                        value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? 'Requested'),
                ),
                const SizedBox(height: 10),
                _sampleDateButton(
                  context: context,
                  label: 'Requested',
                  value: requestedAt,
                  onChanged: (value) =>
                      setDialogState(() => requestedAt = value),
                ),
                _sampleDateButton(
                  context: context,
                  label: 'Expected arrival',
                  value: expectedAt,
                  empty: 'Set expected arrival',
                  onChanged: (value) =>
                      setDialogState(() => expectedAt = value),
                ),
                if (status == 'Received' ||
                    status == 'Testing' ||
                    status == 'Approved' ||
                    status == 'Rejected')
                  _sampleDateButton(
                    context: context,
                    label: 'Received',
                    value: receivedAt,
                    empty: 'Set received date',
                    onChanged: (value) =>
                        setDialogState(() => receivedAt = value),
                  ),
                TextField(
                  controller: courier,
                  decoration: const InputDecoration(labelText: 'Courier'),
                ),
                TextField(
                  controller: tracking,
                  decoration:
                      const InputDecoration(labelText: 'Tracking number'),
                ),
                TextField(
                  controller: sampleCost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Sample cost'),
                ),
                TextField(
                  controller: shippingCost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Shipping cost'),
                ),
                TextField(
                  controller: assignee,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: 'Assigned owner'),
                ),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Test notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'product_id': productId,
                'requested_at': requestedAt.toIso8601String(),
                'expected_at': expectedAt?.toIso8601String(),
                'received_at': receivedAt?.toIso8601String(),
                'status': status,
                'courier': courier.text.trim(),
                'tracking_number': tracking.text.trim(),
                'sample_cost': double.tryParse(sampleCost.text.trim()),
                'shipping_cost': double.tryParse(shippingCost.text.trim()),
                'assignee_email': assignee.text.trim(),
                'test_notes': notes.text.trim(),
              }),
              child: const Text('Save sample'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      courier,
      tracking,
      sampleCost,
      shippingCost,
      assignee,
      notes
    ]) {
      controller.dispose();
    }
    if (result == null) return;
    result['exhibitor_id'] = widget.supplier.id!;
    final id =
        sample == null ? await _db.insert('samples', result) : sample.id!;
    if (sample != null) await _db.update('samples', id, result);
    final expected = expectedAt;
    if (expected != null &&
        status != 'Received' &&
        status != 'Approved' &&
        status != 'Rejected') {
      await ReminderService.scheduleFollowUp(
        id: 2000000 + id,
        title: 'Sample expected today',
        body: widget.supplier.name,
        at: DateTime(expected.year, expected.month, expected.day, 9),
      );
    } else {
      await ReminderService.cancel(2000000 + id);
    }
    if (mounted) setState(_reload);
  }

  Map<String, dynamic> _purchasePlan(Product product) {
    try {
      final value = jsonDecode(product.purchaseReadinessJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<List<_PurchaseReadinessItem>> _loadPurchaseItems() async {
    final products = await _products;
    final samples = await _db.getSamples(exhibitorId: widget.supplier.id!);
    final quotes = (await _db.queryAll('quotes')).map(Quote.fromMap).toList();
    final verification = _verification();
    final verificationApproved = verification['status'] == 'Approved';
    final paymentRisk = _verificationFlag(verification, 'payment_risk');
    final now = DateTime.now();
    return products.map((product) {
      final productSamples = samples
          .where((sample) =>
              sample.productId == null || sample.productId == product.id)
          .toList();
      final productQuotes =
          quotes.where((quote) => quote.productId == product.id).toList();
      final blockers = <String>[
        if (!productSamples.any((sample) => sample.status == 'Approved'))
          'Sample not approved',
        if (!productQuotes.any((quote) =>
            quote.approvalStatus == 'Approved' &&
            (quote.validUntil == null || !quote.validUntil!.isBefore(now))))
          'No active approved quote',
        if (product.moq == null) 'MOQ missing',
        if (product.leadTime.trim().isEmpty) 'Lead time missing',
        if (product.paymentTerms.trim().isEmpty) 'Payment terms missing',
        if (!verificationApproved) 'Supplier verification not approved',
        if (paymentRisk) 'Payment risk flagged',
      ];
      return _PurchaseReadinessItem(product: product, blockers: blockers);
    }).toList();
  }

  Future<void> _editPurchasePlan(_PurchaseReadinessItem item) async {
    final current = _purchasePlan(item.product);
    var status = current['status'] as String? ?? 'Draft';
    var error = '';
    final quantity = TextEditingController(
        text: current['target_quantity']?.toString() ?? '');
    final value = TextEditingController(
        text: current['estimated_order_value']?.toString() ?? '');
    final notes =
        TextEditingController(text: current['notes'] as String? ?? '');
    final poNumber =
        TextEditingController(text: current['po_number'] as String? ?? '');
    var productionStatus =
        current['production_status'] as String? ?? 'Not started';
    var deliveryStatus = current['delivery_status'] as String? ?? 'Not booked';
    DateTime? productionDue =
        DateTime.tryParse(current['production_due'] as String? ?? '');
    DateTime? deliveryDue =
        DateTime.tryParse(current['delivery_due'] as String? ?? '');
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Purchase readiness: ${item.product.name}'),
          content: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration:
                        const InputDecoration(labelText: 'Handover status'),
                    items: const [
                      DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                      DropdownMenuItem(
                          value: 'Needs review', child: Text('Needs review')),
                      DropdownMenuItem(
                          value: 'Ready to order',
                          child: Text('Ready to order')),
                      DropdownMenuItem(
                          value: 'Approved for order',
                          child: Text('Approved for order')),
                    ],
                    onChanged: (next) =>
                        setDialogState(() => status = next ?? 'Draft'),
                  ),
                  TextField(
                      controller: quantity,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Target quantity')),
                  TextField(
                      controller: value,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Estimated order value')),
                  TextField(
                    controller: poNumber,
                    decoration: const InputDecoration(
                        labelText: 'PO number / draft reference'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: productionStatus,
                    decoration:
                        const InputDecoration(labelText: 'Production status'),
                    items: const [
                      'Not started',
                      'Factory confirmed',
                      'In production',
                      'Quality check',
                      'Ready to ship',
                    ]
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setDialogState(
                        () => productionStatus = value ?? productionStatus),
                  ),
                  _sampleDateButton(
                    context: dialogContext,
                    label: 'Production due',
                    value: productionDue,
                    empty: 'Set production due date',
                    onChanged: (value) =>
                        setDialogState(() => productionDue = value),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: deliveryStatus,
                    decoration:
                        const InputDecoration(labelText: 'Delivery status'),
                    items: const [
                      'Not booked',
                      'Booked',
                      'Shipped',
                      'Delivered'
                    ]
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setDialogState(
                        () => deliveryStatus = value ?? deliveryStatus),
                  ),
                  _sampleDateButton(
                    context: dialogContext,
                    label: 'Delivery due',
                    value: deliveryDue,
                    empty: 'Set delivery due date',
                    onChanged: (value) =>
                        setDialogState(() => deliveryDue = value),
                  ),
                  TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Procurement notes')),
                  if (item.blockers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Current blockers',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    ...item.blockers.map((blocker) => Text('- $blocker')),
                  ],
                  if (error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error,
                            style: const TextStyle(color: AppColors.danger))),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (status == 'Ready to order' && item.blockers.isNotEmpty) {
                  setDialogState(() => error =
                      'Resolve all blockers before marking this ready to order.');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'status': status,
                  'target_quantity': double.tryParse(quantity.text.trim()),
                  'estimated_order_value': double.tryParse(value.text.trim()),
                  'po_number': poNumber.text.trim(),
                  'production_status': productionStatus,
                  'production_due': productionDue?.toIso8601String(),
                  'delivery_status': deliveryStatus,
                  'delivery_due': deliveryDue?.toIso8601String(),
                  'notes': notes.text.trim(),
                  'updated_at': DateTime.now().toIso8601String(),
                });
              },
              child: const Text('Save handover'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    value.dispose();
    notes.dispose();
    poNumber.dispose();
    if (result == null) return;
    await _db.update('products', item.product.id!,
        {'purchase_readiness_json': jsonEncode(result)});
    if (mounted) setState(_reload);
  }

  Future<void> _sharePurchaseReady() async {
    final items = await _loadPurchaseItems();
    final ready = items.where((item) {
      final status = _purchasePlan(item.product)['status'];
      return status == 'Ready to order' || status == 'Approved for order';
    }).toList();
    final lines = [
      'Canton Fair purchase handover: ${widget.supplier.name}',
      if (ready.isEmpty) 'No products are purchase-ready yet.',
      ...ready.map((item) {
        final plan = _purchasePlan(item.product);
        return '${item.product.name} | ${plan['status']} | Qty ${plan['target_quantity'] ?? '-'} | Value ${plan['estimated_order_value'] ?? '-'}';
      }),
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  Widget _sampleDateButton({
    required BuildContext context,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onChanged,
    String empty = 'Choose date',
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.event_outlined),
          label: Text(value == null
              ? '$label: $empty'
              : '$label: ${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'),
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (selected != null) onChanged(selected);
          },
        ),
      );

  Map<String, dynamic> _fieldCapture(Exhibitor supplier) {
    try {
      final value = jsonDecode(_fieldCaptureJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  Future<void> _editFairIntelligence() async {
    final data = _fieldCapture(widget.supplier);
    final competitor =
        TextEditingController(text: data['competitor_group'] as String? ?? '');
    final decisionMaker =
        TextEditingController(text: data['decision_maker'] as String? ?? '');
    final demoNotes =
        TextEditingController(text: data['live_demo_notes'] as String? ?? '');
    final availability = TextEditingController(
        text: data['availability_notes'] as String? ?? '');
    final exclusivity = TextEditingController(
        text: data['exclusivity_discussion'] as String? ?? '');
    final factoryVisit = TextEditingController(
        text: data['factory_visit_request'] as String? ?? '');
    final compliance =
        TextEditingController(text: data['market_compliance'] as String? ?? '');
    final redFlagEvidence =
        TextEditingController(text: data['red_flag_evidence'] as String? ?? '');
    final voiceSummary = TextEditingController(
        text: data['structured_voice_summary'] as String? ?? '');
    final postFairReview =
        TextEditingController(text: data['post_fair_review'] as String? ?? '');
    final revisitReason =
        TextEditingController(text: data['revisit_reason'] as String? ?? '');
    final marketNotes = TextEditingController(
        text: data['market_trend_notes'] as String? ?? '');
    final positioning = TextEditingController(
        text: data['market_positioning'] as String? ?? '');
    var relationship = data['relationship_strength'] as int? ?? 0;
    var ownerMet = data['owner_met'] == true;
    var opportunityScore = data['product_opportunity_score'] as int? ?? 0;
    var boothTraffic = data['booth_traffic'] as String? ?? 'Not recorded';
    var displayQuality = data['display_quality'] as String? ?? 'Not recorded';
    var catalogueReceived = data['catalogue_received'] == true;
    var qrScanned = data['qr_scanned'] == true;
    var wechatAdded = data['wechat_added'] == true;
    var revisitNeeded = data['revisit_needed'] == true;
    final boothEvidence = <String>{..._stringList(data['booth_evidence'])};
    final impressions = <String>{..._stringList(data['impressions'])};
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Fair intelligence'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: relationship,
                  decoration:
                      const InputDecoration(labelText: 'Relationship strength'),
                  items: List.generate(
                      6,
                      (value) => DropdownMenuItem(
                          value: value,
                          child:
                              Text(value == 0 ? 'Not rated' : '$value / 5'))),
                  onChanged: (value) =>
                      setDialogState(() => relationship = value ?? 0),
                ),
                TextField(
                  controller: decisionMaker,
                  decoration:
                      const InputDecoration(labelText: 'Decision-maker met'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: ownerMet,
                  title:
                      const Text('Factory owner / senior decision-maker met'),
                  onChanged: (value) => setDialogState(() => ownerMet = value),
                ),
                TextField(
                  controller: competitor,
                  decoration: const InputDecoration(
                      labelText: 'Competitor / alternative group'),
                ),
                const SizedBox(height: 16),
                const Text('Booth evidence',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(
                  spacing: 8,
                  children: const [
                    'Exterior photo',
                    'Interior photo',
                    'Product display',
                    'Catalogue captured'
                  ]
                      .map((label) => FilterChip(
                            label: Text(label),
                            selected: boothEvidence.contains(label),
                            onSelected: (selected) => setDialogState(() {
                              if (selected) {
                                boothEvidence.add(label);
                              } else {
                                boothEvidence.remove(label);
                              }
                            }),
                          ))
                      .toList(),
                ),
                DropdownButtonFormField<String>(
                  initialValue: boothTraffic,
                  decoration:
                      const InputDecoration(labelText: 'Booth visitor traffic'),
                  items: const [
                    'Not recorded',
                    'Quiet',
                    'Steady',
                    'Busy',
                    'Very busy'
                  ]
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(
                      () => boothTraffic = value ?? 'Not recorded'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: displayQuality,
                  decoration: const InputDecoration(
                      labelText: 'Product display quality'),
                  items: const ['Not recorded', 'Basic', 'Good', 'Excellent']
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(
                      () => displayQuality = value ?? 'Not recorded'),
                ),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: catalogueReceived,
                    title: const Text('Catalogue / price list received'),
                    onChanged: (value) =>
                        setDialogState(() => catalogueReceived = value)),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: qrScanned,
                    title: const Text('Supplier QR code scanned'),
                    onChanged: (value) =>
                        setDialogState(() => qrScanned = value)),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: wechatAdded,
                    title: const Text('WeChat contact added'),
                    onChanged: (value) =>
                        setDialogState(() => wechatAdded = value)),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: revisitNeeded,
                    title: const Text('Revisit this booth'),
                    onChanged: (value) =>
                        setDialogState(() => revisitNeeded = value)),
                if (revisitNeeded)
                  TextField(
                      controller: revisitReason,
                      decoration: const InputDecoration(
                          labelText: 'Why revisit / what to check next')),
                TextField(
                    controller: demoNotes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText:
                            'Live product demo: observations and questions')),
                TextField(
                    controller: availability,
                    decoration: const InputDecoration(
                        labelText: 'Availability / production window')),
                TextField(
                    controller: exclusivity,
                    decoration: const InputDecoration(
                        labelText: 'Exclusive distributor discussion')),
                TextField(
                    controller: factoryVisit,
                    decoration: const InputDecoration(
                        labelText: 'Factory visit request / next step')),
                TextField(
                    controller: compliance,
                    decoration: const InputDecoration(
                        labelText: 'Compliance by market (EU, US, GCC, etc.)')),
                TextField(
                    controller: redFlagEvidence,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Red-flag evidence and photo reference')),
                DropdownButtonFormField<int>(
                  initialValue: opportunityScore,
                  decoration: const InputDecoration(
                      labelText: 'Product opportunity score'),
                  items: List.generate(
                      6,
                      (value) => DropdownMenuItem(
                          value: value,
                          child:
                              Text(value == 0 ? 'Not rated' : '$value / 5'))),
                  onChanged: (value) =>
                      setDialogState(() => opportunityScore = value ?? 0),
                ),
                TextField(
                    controller: voiceSummary,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Voice capture summary (facts extracted)')),
                TextField(
                    controller: postFairReview,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Post-fair team review / decision')),
                TextField(
                    controller: positioning,
                    decoration: const InputDecoration(
                        labelText: 'Market positioning / price band')),
                TextField(
                    controller: marketNotes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText:
                            'Market trends, packaging, and competitor observations')),
                const SizedBox(height: 8),
                const Text('What impressed you?',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: const [
                    'Quality',
                    'Innovation',
                    'Best seller',
                    'New launch',
                    'Price advantage',
                    'Packaging',
                    'Fast response',
                    'Red flag'
                  ]
                      .map((label) => FilterChip(
                            label: Text(label),
                            selected: impressions.contains(label),
                            onSelected: (selected) => setDialogState(() {
                              if (selected) {
                                impressions.add(label);
                              } else {
                                impressions.remove(label);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'relationship_strength': relationship,
                'decision_maker': decisionMaker.text.trim(),
                'owner_met': ownerMet,
                'competitor_group': competitor.text.trim(),
                'impressions': impressions.toList(),
                'booth_evidence': boothEvidence.toList(),
                'live_demo_notes': demoNotes.text.trim(),
                'availability_notes': availability.text.trim(),
                'exclusivity_discussion': exclusivity.text.trim(),
                'factory_visit_request': factoryVisit.text.trim(),
                'market_compliance': compliance.text.trim(),
                'red_flag_evidence': redFlagEvidence.text.trim(),
                'product_opportunity_score': opportunityScore,
                'structured_voice_summary': voiceSummary.text.trim(),
                'post_fair_review': postFairReview.text.trim(),
                'booth_traffic': boothTraffic,
                'display_quality': displayQuality,
                'catalogue_received': catalogueReceived,
                'qr_scanned': qrScanned,
                'wechat_added': wechatAdded,
                'revisit_needed': revisitNeeded,
                'revisit_reason': revisitReason.text.trim(),
                'market_positioning': positioning.text.trim(),
                'market_trend_notes': marketNotes.text.trim(),
              }),
              child: const Text('Save intelligence'),
            ),
          ],
        ),
      ),
    );
    competitor.dispose();
    decisionMaker.dispose();
    demoNotes.dispose();
    availability.dispose();
    exclusivity.dispose();
    factoryVisit.dispose();
    compliance.dispose();
    redFlagEvidence.dispose();
    voiceSummary.dispose();
    postFairReview.dispose();
    revisitReason.dispose();
    marketNotes.dispose();
    positioning.dispose();
    if (result == null) return;
    data.addAll(result);
    final encoded = jsonEncode(data);
    await _db.update(
        'exhibitors', widget.supplier.id!, {'field_capture_json': encoded});
    if (mounted) setState(() => _fieldCaptureJson = encoded);
  }

  Future<void> _toggleVisitTimer() async {
    final data = _fieldCapture(widget.supplier);
    final started =
        DateTime.tryParse(data['active_visit_started_at'] as String? ?? '');
    if (started == null) {
      data['active_visit_started_at'] = DateTime.now().toIso8601String();
      final encoded = jsonEncode(data);
      await _db.update('exhibitors', widget.supplier.id!, {
        'field_capture_json': encoded,
        'visited_at': DateTime.now().toIso8601String(),
      });
      if (mounted) setState(() => _fieldCaptureJson = encoded);
      return;
    }
    final visits = <Map<String, dynamic>>[];
    final rawVisits = data['visit_log'];
    if (rawVisits is List) {
      visits.addAll(rawVisits
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
    }
    final ended = DateTime.now();
    visits.add({
      'started_at': started.toIso8601String(),
      'ended_at': ended.toIso8601String(),
      'minutes': ended.difference(started).inMinutes,
    });
    data.remove('active_visit_started_at');
    data['visit_log'] = visits;
    final encoded = jsonEncode(data);
    await _db.update('exhibitors', widget.supplier.id!,
        {'field_capture_json': encoded, 'visited_at': ended.toIso8601String()});
    if (mounted) setState(() => _fieldCaptureJson = encoded);
  }

  Map<String, dynamic> _verification() {
    try {
      final value = jsonDecode(_verificationJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  bool _verificationFlag(Map<String, dynamic> data, String key) =>
      data[key] == true;

  Map<String, dynamic> _commitments(Meeting meeting) {
    try {
      final value = jsonDecode(meeting.commitmentsJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _productDetails(Product product) {
    try {
      final value = jsonDecode(product.detailsJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _contactProfile(Contact contact) {
    try {
      final value = jsonDecode(contact.profileJson);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _editNegotiation(Product product) async {
    final details = _productDetails(product);
    final existing = details['negotiation'] is Map
        ? Map<String, dynamic>.from(details['negotiation'] as Map)
        : <String, dynamic>{};
    final firstPrice = TextEditingController(
        text: existing['first_price']?.toString() ??
            product.quotedPrice?.toString() ??
            '');
    final targetPrice =
        TextEditingController(text: existing['target_price']?.toString() ?? '');
    final negotiatedPrice = TextEditingController(
        text: existing['negotiated_price']?.toString() ?? '');
    final incoterm =
        TextEditingController(text: existing['incoterm'] as String? ?? '');
    final condition =
        TextEditingController(text: existing['condition'] as String? ?? '');
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Negotiation: ${product.name}'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: firstPrice,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'First price')),
            TextField(
                controller: targetPrice,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Target price')),
            TextField(
                controller: negotiatedPrice,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Negotiated price')),
            TextField(
                controller: incoterm,
                decoration: const InputDecoration(
                    labelText: 'Incoterm (EXW / FOB / CIF)')),
            TextField(
                controller: condition,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Discount condition / price validity')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, {
                    'first_price': double.tryParse(firstPrice.text.trim()),
                    'target_price': double.tryParse(targetPrice.text.trim()),
                    'negotiated_price':
                        double.tryParse(negotiatedPrice.text.trim()),
                    'incoterm': incoterm.text.trim(),
                    'condition': condition.text.trim(),
                    'updated_at': DateTime.now().toIso8601String(),
                  }),
              child: const Text('Save negotiation')),
        ],
      ),
    );
    firstPrice.dispose();
    targetPrice.dispose();
    negotiatedPrice.dispose();
    incoterm.dispose();
    condition.dispose();
    if (result == null) return;
    details['negotiation'] = result;
    await _db
        .update('products', product.id!, {'details_json': jsonEncode(details)});
    if (mounted) setState(_reload);
  }

  Future<void> _editVerification() async {
    final existing = _verification();
    var companyType = existing['company_type'] as String? ?? 'Not verified';
    var sampleStatus = existing['sample_status'] as String? ?? 'Not requested';
    var verificationStatus = existing['status'] as String? ?? 'Unverified';
    var certificatesVerified =
        _verificationFlag(existing, 'certificates_verified');
    var factoryAuditRequired =
        _verificationFlag(existing, 'factory_audit_required');
    var paymentRisk = _verificationFlag(existing, 'payment_risk');
    var communicationRisk = _verificationFlag(existing, 'communication_risk');
    var qualityRisk = _verificationFlag(existing, 'quality_risk');
    var ipRisk = _verificationFlag(existing, 'ip_risk');
    var complianceRisk = _verificationFlag(existing, 'compliance_risk');
    var tradingRisk = _verificationFlag(existing, 'trading_company_risk');
    var capacityRisk = _verificationFlag(existing, 'capacity_risk');
    final yearsController = TextEditingController(
        text: existing['years_exporting'] as String? ?? '');
    final marketsController = TextEditingController(
        text: existing['export_markets'] as String? ?? '');
    final notesController =
        TextEditingController(text: existing['notes'] as String? ?? '');
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Supplier verification'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: verificationStatus,
                  decoration:
                      const InputDecoration(labelText: 'Verification status'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Unverified', child: Text('Unverified')),
                    DropdownMenuItem(
                        value: 'In review', child: Text('In review')),
                    DropdownMenuItem(
                        value: 'Approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'Blocked', child: Text('Blocked')),
                  ],
                  onChanged: (value) => setDialogState(
                      () => verificationStatus = value ?? 'Unverified'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: companyType,
                  decoration: const InputDecoration(labelText: 'Supplier type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Not verified', child: Text('Not verified')),
                    DropdownMenuItem(
                        value: 'Manufacturer', child: Text('Manufacturer')),
                    DropdownMenuItem(
                        value: 'Trading company',
                        child: Text('Trading company')),
                  ],
                  onChanged: (value) => setDialogState(
                      () => companyType = value ?? 'Not verified'),
                ),
                TextField(
                  controller: yearsController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Years exporting'),
                ),
                TextField(
                  controller: marketsController,
                  decoration:
                      const InputDecoration(labelText: 'Main export markets'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: certificatesVerified,
                  title: const Text('Certificates verified'),
                  subtitle: const Text('Keep certificate proof in Files.'),
                  onChanged: (value) =>
                      setDialogState(() => certificatesVerified = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: sampleStatus,
                  decoration: const InputDecoration(labelText: 'Sample status'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Not requested', child: Text('Not requested')),
                    DropdownMenuItem(
                        value: 'Requested', child: Text('Requested')),
                    DropdownMenuItem(
                        value: 'Received', child: Text('Received')),
                    DropdownMenuItem(
                        value: 'Approved', child: Text('Approved')),
                    DropdownMenuItem(
                        value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: (value) => setDialogState(
                      () => sampleStatus = value ?? 'Not requested'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: factoryAuditRequired,
                  title: const Text('Factory audit required'),
                  onChanged: (value) =>
                      setDialogState(() => factoryAuditRequired = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: paymentRisk,
                  title: const Text('Payment risk'),
                  onChanged: (value) =>
                      setDialogState(() => paymentRisk = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: communicationRisk,
                  title: const Text('Communication risk'),
                  onChanged: (value) =>
                      setDialogState(() => communicationRisk = value),
                ),
                const SizedBox(height: 4),
                const Text('Supplier risk checklist',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: qualityRisk,
                  title: const Text('Quality risk'),
                  onChanged: (value) =>
                      setDialogState(() => qualityRisk = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: ipRisk,
                  title: const Text('IP / design-copy risk'),
                  onChanged: (value) => setDialogState(() => ipRisk = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: complianceRisk,
                  title: const Text('Compliance risk'),
                  onChanged: (value) =>
                      setDialogState(() => complianceRisk = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: tradingRisk,
                  title: const Text('Trading-company risk'),
                  onChanged: (value) =>
                      setDialogState(() => tradingRisk = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: capacityRisk,
                  title: const Text('Production-capacity risk'),
                  onChanged: (value) =>
                      setDialogState(() => capacityRisk = value),
                ),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Verification notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'certificates': existing['certificates'] ?? const [],
                'status': verificationStatus,
                'company_type': companyType,
                'years_exporting': yearsController.text.trim(),
                'export_markets': marketsController.text.trim(),
                'certificates_verified': certificatesVerified,
                'sample_status': sampleStatus,
                'factory_audit_required': factoryAuditRequired,
                'payment_risk': paymentRisk,
                'communication_risk': communicationRisk,
                'quality_risk': qualityRisk,
                'ip_risk': ipRisk,
                'compliance_risk': complianceRisk,
                'trading_company_risk': tradingRisk,
                'capacity_risk': capacityRisk,
                'notes': notesController.text.trim(),
                'updated_at': DateTime.now().toIso8601String(),
              }),
              child: const Text('Save verification'),
            ),
          ],
        ),
      ),
    );
    yearsController.dispose();
    marketsController.dispose();
    notesController.dispose();
    if (result == null) return;
    final encoded = jsonEncode(result);
    await _db.update(
        'exhibitors', widget.supplier.id!, {'verification_json': encoded});
    if (mounted) setState(() => _verificationJson = encoded);
  }

  List<Map<String, dynamic>> _certificates(Map<String, dynamic> data) {
    final certificates = data['certificates'];
    if (certificates is! List) return const [];
    return certificates
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _editCertificate(
      [Map<String, dynamic>? certificate, int? certificateIndex]) async {
    final typeController = TextEditingController(
        text: certificate?['type'] as String? ?? 'ISO 9001');
    final numberController =
        TextEditingController(text: certificate?['number'] as String? ?? '');
    final issuerController =
        TextEditingController(text: certificate?['issuer'] as String? ?? '');
    var expiry = DateTime.tryParse(certificate?['expiry'] as String? ?? '');
    var verified = certificate?['verified'] == true;
    final selectedChecks = <String>{
      ...(certificate?['checks'] as List? ?? const []).whereType<String>(),
    };
    const checkOptions = [
      'Certificate copy attached',
      'Issuer checked',
      'Expiry checked',
      'Scope matches products',
    ];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              certificate == null ? 'Add certificate' : 'Edit certificate'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: typeController.text,
                  decoration:
                      const InputDecoration(labelText: 'Certificate type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'ISO 9001', child: Text('ISO 9001')),
                    DropdownMenuItem(value: 'CE', child: Text('CE')),
                    DropdownMenuItem(value: 'RoHS', child: Text('RoHS')),
                    DropdownMenuItem(value: 'REACH', child: Text('REACH')),
                    DropdownMenuItem(value: 'FDA', child: Text('FDA')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) => typeController.text = value ?? 'Other',
                ),
                TextField(
                  controller: numberController,
                  decoration:
                      const InputDecoration(labelText: 'Certificate number'),
                ),
                TextField(
                  controller: issuerController,
                  decoration:
                      const InputDecoration(labelText: 'Issuer / authority'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(expiry == null
                      ? 'Expiry date: not recorded'
                      : 'Expiry date: ${expiry!.year.toString().padLeft(4, '0')}-${expiry!.month.toString().padLeft(2, '0')}-${expiry!.day.toString().padLeft(2, '0')}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: expiry ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2050),
                    );
                    if (picked != null) setDialogState(() => expiry = picked);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: verified,
                  title: const Text('Verified'),
                  onChanged: (value) => setDialogState(() => verified = value),
                ),
                const Text('Compliance checklist',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                ...checkOptions.map((check) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selectedChecks.contains(check),
                      title: Text(check),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selectedChecks.add(check);
                        } else {
                          selectedChecks.remove(check);
                        }
                      }),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'type': typeController.text,
                'number': numberController.text.trim(),
                'issuer': issuerController.text.trim(),
                'expiry': expiry?.toIso8601String(),
                'verified': verified,
                'checks': selectedChecks.toList(),
              }),
              child: const Text('Save certificate'),
            ),
          ],
        ),
      ),
    );
    typeController.dispose();
    numberController.dispose();
    issuerController.dispose();
    if (result == null) return;
    final data = _verification();
    final certificates = _certificates(data);
    if (certificate == null) {
      certificates.add(result);
    } else {
      final index = certificateIndex ?? -1;
      if (index >= 0) certificates[index] = result;
    }
    data['certificates'] = certificates;
    data['certificates_verified'] = certificates.isNotEmpty &&
        certificates.every((item) => item['verified'] == true);
    data['updated_at'] = DateTime.now().toIso8601String();
    final encoded = jsonEncode(data);
    await _db.update(
        'exhibitors', widget.supplier.id!, {'verification_json': encoded});
    if (mounted) setState(() => _verificationJson = encoded);
  }

  Future<void> _deleteCertificate(int certificateIndex) async {
    final data = _verification();
    final certificates = _certificates(data);
    if (certificateIndex >= 0 && certificateIndex < certificates.length) {
      certificates.removeAt(certificateIndex);
    }
    data['certificates'] = certificates;
    data['certificates_verified'] = certificates.isNotEmpty &&
        certificates.every((item) => item['verified'] == true);
    final encoded = jsonEncode(data);
    await _db.update(
        'exhibitors', widget.supplier.id!, {'verification_json': encoded});
    if (mounted) setState(() => _verificationJson = encoded);
  }

  Widget _fieldCapturePanel(Exhibitor supplier) {
    final capture = _fieldCapture(supplier);
    if (capture.isEmpty) return const SizedBox.shrink();
    final checklist = (capture['checklist'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final details = <(String, String)>[
      ('Type', capture['company_type'] as String? ?? ''),
      ('OEM / ODM', capture['oem_odm'] as String? ?? ''),
      ('Factory', capture['factory_location'] as String? ?? ''),
      ('Markets', capture['export_markets'] as String? ?? ''),
      ('Capacity', capture['production_capacity'] as String? ?? ''),
      ('Employees', capture['employee_count'] as String? ?? ''),
      ('Factory size', capture['factory_size'] as String? ?? ''),
      ('Audit', capture['audit_status'] as String? ?? ''),
      ('Certificates', capture['certifications'] as String? ?? ''),
    ]
        .where((detail) => detail.$2.isNotEmpty && detail.$2 != 'Not recorded')
        .toList();
    return Column(
      children: [
        const SizedBox(height: 16),
        SectionPanel(
          title: 'On-site capture',
          subtitle: 'Details recorded during the Canton Fair visit.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (details.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: details
                      .map((detail) =>
                          InfoChip(label: '${detail.$1}: ${detail.$2}'))
                      .toList(),
                ),
              if (checklist.isNotEmpty) ...[
                if (details.isNotEmpty) const SizedBox(height: 12),
                const Text('Confirmed at booth',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: checklist
                      .map((label) => InfoChip(
                          label: label,
                          icon: Icons.check_circle_outline,
                          color: AppColors.teal))
                      .toList(),
                ),
              ],
              if (details.isEmpty && checklist.isEmpty)
                const Text(
                    'The field checklist was started without additional details.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(String title, String message, IconData icon) => EmptyState(
        title: title,
        message: message,
        icon: icon,
      );

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(supplier.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Share supplier summary',
              onPressed: _shareSummary,
              icon: const Icon(Icons.ios_share_outlined),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Contacts'),
              Tab(text: 'Products'),
              Tab(text: 'Meetings'),
              Tab(text: 'Files'),
              Tab(text: 'Verification'),
              Tab(text: 'Samples'),
              Tab(text: 'Purchase'),
              Tab(text: 'Scorecard'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _overview(supplier),
            _contactsTab(),
            _productsTab(),
            _meetingsTab(),
            _filesTab(),
            _verificationTab(),
            _samplesTab(),
            _purchaseTab(),
            _scorecard(supplier),
          ],
        ),
      ),
    );
  }

  Widget _fairIntelligencePanel() {
    final data = _fieldCapture(widget.supplier);
    final impressions = _stringList(data['impressions']);
    final boothEvidence = _stringList(data['booth_evidence']);
    final activeVisit =
        DateTime.tryParse(data['active_visit_started_at'] as String? ?? '');
    final visits = data['visit_log'] as List? ?? const [];
    return SectionPanel(
      title: 'Fair intelligence',
      subtitle: 'Capture what you observed, who mattered, and alternatives.',
      trailing: IconButton(
        tooltip: 'Edit fair intelligence',
        icon: const Icon(Icons.edit_outlined),
        onPressed: _editFairIntelligence,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((data['relationship_strength'] as int? ?? 0) > 0)
                InfoChip(
                    label: 'Relationship ${data['relationship_strength']}/5',
                    icon: Icons.handshake_outlined,
                    color: AppColors.teal),
              if ((data['decision_maker'] as String? ?? '').isNotEmpty)
                InfoChip(label: 'Decision-maker: ${data['decision_maker']}'),
              if (data['owner_met'] == true)
                const InfoChip(
                    label: 'Owner met', icon: Icons.person_pin_outlined),
              if ((data['competitor_group'] as String? ?? '').isNotEmpty)
                InfoChip(label: 'Alternative: ${data['competitor_group']}'),
              if ((data['product_opportunity_score'] as int? ?? 0) > 0)
                InfoChip(
                    label: 'Opportunity ${data['product_opportunity_score']}/5',
                    icon: Icons.auto_awesome_outlined,
                    color: AppColors.amber),
              if ((data['booth_traffic'] as String? ?? 'Not recorded') !=
                  'Not recorded')
                InfoChip(
                    label: 'Traffic: ${data['booth_traffic']}',
                    icon: Icons.groups_outlined),
              if ((data['display_quality'] as String? ?? 'Not recorded') !=
                  'Not recorded')
                InfoChip(
                    label: 'Display: ${data['display_quality']}',
                    icon: Icons.storefront_outlined),
              if (data['catalogue_received'] == true)
                const InfoChip(
                    label: 'Catalogue received',
                    icon: Icons.menu_book_outlined),
              if (data['qr_scanned'] == true)
                const InfoChip(
                    label: 'QR scanned', icon: Icons.qr_code_scanner_outlined),
              if (data['wechat_added'] == true)
                const InfoChip(
                    label: 'WeChat added', icon: Icons.chat_outlined),
              if (data['revisit_needed'] == true)
                const InfoChip(
                    label: 'Revisit needed',
                    icon: Icons.replay_outlined,
                    color: AppColors.amber),
              ...impressions.map((item) => InfoChip(label: item)),
              ...boothEvidence.map((item) =>
                  InfoChip(label: item, icon: Icons.camera_alt_outlined)),
            ],
          ),
          ...[
            ('Live demo', data['live_demo_notes']),
            ('Availability', data['availability_notes']),
            ('Exclusivity', data['exclusivity_discussion']),
            ('Factory visit', data['factory_visit_request']),
            ('Market compliance', data['market_compliance']),
            ('Red-flag evidence', data['red_flag_evidence']),
            ('Voice summary', data['structured_voice_summary']),
            ('Post-fair review', data['post_fair_review']),
            ('Revisit reason', data['revisit_reason']),
            ('Market position', data['market_positioning']),
            ('Trend notes', data['market_trend_notes']),
          ]
              .where((item) => (item.$2 as String? ?? '').isNotEmpty)
              .map((item) => Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('${item.$1}: ${item.$2}',
                        style: const TextStyle(color: AppColors.muted)),
                  )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _toggleVisitTimer,
            icon: Icon(activeVisit == null
                ? Icons.play_circle_outline
                : Icons.stop_circle_outlined),
            label: Text(activeVisit == null
                ? 'Start booth visit timer'
                : 'Finish booth visit (${DateTime.now().difference(activeVisit).inMinutes} min)'),
          ),
          if (visits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
                '${visits.length} visit${visits.length == 1 ? '' : 's'} recorded',
                style: const TextStyle(color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _overview(Exhibitor supplier) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(
                  label: supplier.booth.isEmpty
                      ? 'Booth not recorded'
                      : 'Booth ${supplier.booth}',
                  icon: Icons.place),
              if (supplier.hall.isNotEmpty)
                InfoChip(
                    label: supplier.hall,
                    icon: Icons.location_city,
                    color: AppColors.teal),
              if (supplier.shortlisted)
                const InfoChip(
                    label: 'Shortlisted',
                    icon: Icons.star,
                    color: Color(0xFF2F855A)),
              InfoChip(
                  label:
                      supplier.visitedAt == null ? 'Need to visit' : 'Visited',
                  icon: supplier.visitedAt == null
                      ? Icons.route_outlined
                      : Icons.task_alt,
                  color: supplier.visitedAt == null
                      ? AppColors.amber
                      : AppColors.teal),
              InfoChip(
                label: _decision,
                icon: _decision == 'Shortlist'
                    ? Icons.star
                    : _decision == 'Reject'
                        ? Icons.block_outlined
                        : Icons.help_outline,
                color: _decision == 'Shortlist'
                    ? const Color(0xFF2F855A)
                    : _decision == 'Reject'
                        ? AppColors.danger
                        : AppColors.amber,
              ),
              _verificationChip(),
            ],
          ),
          const SizedBox(height: 18),
          SectionPanel(
            title: 'Supplier decision',
            subtitle:
                'Make a sourcing decision while the conversation is fresh.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                    label: const Text('Shortlist'),
                    selected: _decision == 'Shortlist',
                    onSelected: (_) => _setDecision('Shortlist')),
                ChoiceChip(
                    label: const Text('Maybe'),
                    selected: _decision == 'Maybe',
                    onSelected: (_) => _setDecision('Maybe')),
                ChoiceChip(
                    label: const Text('Reject'),
                    selected: _decision == 'Reject',
                    onSelected: (_) => _setDecision('Reject')),
              ],
            ),
          ),
          _fieldCapturePanel(supplier),
          const SizedBox(height: 16),
          _fairIntelligencePanel(),
          const SizedBox(height: 16),
          SectionPanel(
            title: 'Supplier notes',
            child: Text(supplier.contactCompanyNotes.isEmpty
                ? 'No supplier notes recorded yet.'
                : supplier.contactCompanyNotes),
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (tabContext) => SectionPanel(
              title: 'Quick actions',
              subtitle:
                  'Use the Contacts tab to call or message a specific person.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                      onPressed: _shareSummary,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share summary')),
                  OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(tabContext).animateTo(3),
                      icon: const Icon(Icons.event_note_outlined),
                      label: const Text('View tasks')),
                  OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(tabContext).animateTo(4),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('View files')),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _contactsTab() => FutureBuilder<List<Contact>>(
        future: _contacts,
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? const <Contact>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (contacts.isEmpty) {
            return _empty(
                'No contacts',
                'Add a contact from the supplier capture screen.',
                Icons.person_add_alt_1_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final profile = _contactProfile(contact);
              return Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(
                      contact.name.isEmpty ? 'Unnamed contact' : contact.name),
                  subtitle: Text([
                    contact.designation,
                    contact.phone,
                    contact.email,
                    if ((profile['influence'] as String? ?? '').isNotEmpty &&
                        profile['influence'] != 'Not recorded')
                      profile['influence'] as String,
                    if ((profile['language'] as String? ?? '').isNotEmpty)
                      profile['language'] as String,
                  ].where((item) => item.isNotEmpty).join('\n')),
                  isThreeLine: contact.designation.isNotEmpty &&
                      contact.phone.isNotEmpty,
                  trailing: Wrap(
                    children: [
                      if (contact.phone.isNotEmpty)
                        IconButton(
                            tooltip: 'Call',
                            onPressed: () => _openPhone(contact.phone),
                            icon: const Icon(Icons.call_outlined)),
                      if (contact.whatsapp.isNotEmpty ||
                          contact.phone.isNotEmpty)
                        IconButton(
                            tooltip: 'WhatsApp',
                            onPressed: () => _openPhone(
                                contact.whatsapp.isEmpty
                                    ? contact.phone
                                    : contact.whatsapp,
                                whatsapp: true),
                            icon: const Icon(Icons.chat_outlined)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _productsTab() => FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <Product>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (products.isEmpty) {
            return _empty(
                'No products',
                'Add products from the supplier capture screen.',
                Icons.inventory_2_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              final details = _productDetails(product);
              final negotiation = details['negotiation'] is Map
                  ? Map<String, dynamic>.from(details['negotiation'] as Map)
                  : const <String, dynamic>{};
              final detailText = <String>[
                if ((details['materials'] as String? ?? '').isNotEmpty)
                  'Material: ${details['materials']}',
                if ((details['dimensions'] as String? ?? '').isNotEmpty)
                  'Size: ${details['dimensions']}',
                if ((details['colours'] as String? ?? '').isNotEmpty)
                  'Colours: ${details['colours']}',
                if ((details['packaging'] as String? ?? '').isNotEmpty)
                  'Packaging: ${details['packaging']}',
                if (details['best_seller'] == true) 'Best seller',
                if (details['new_product'] == true) 'New product',
                if (negotiation['negotiated_price'] != null)
                  'Negotiated: ${negotiation['negotiated_price']} ${product.priceCurrency}',
              ];
              return Card(
                  child: ListTile(
                title: Text(product.name),
                subtitle: Text([
                  'MOQ ${product.moq ?? '-'} | ${product.quotedPrice == null ? 'No quote' : '${product.quotedPrice} ${product.priceCurrency}'} | ${product.leadTime.isEmpty ? 'No lead time' : product.leadTime}',
                  ...detailText,
                ].join('\n')),
                isThreeLine: detailText.isNotEmpty,
                trailing: PopupMenuButton<String>(
                  tooltip: 'Product actions',
                  onSelected: (value) {
                    if (value == 'negotiation') _editNegotiation(product);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'negotiation',
                        child: Text('Record negotiation')),
                  ],
                ),
              ));
            },
          );
        },
      );

  Widget _meetingsTab() => FutureBuilder<List<Meeting>>(
        future: _meetings,
        builder: (context, snapshot) {
          final meetings = snapshot.data ?? const <Meeting>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (meetings.isEmpty) {
            return _empty(
                'No follow-ups',
                'Create a follow-up from the supplier capture screen.',
                Icons.event_note_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final meeting = meetings[index];
              final commitments = _commitments(meeting);
              final supplierCommitment =
                  commitments['supplier'] as String? ?? '';
              final ourCommitment = commitments['ours'] as String? ?? '';
              final lines = <String>[
                '${meeting.priority} priority${meeting.assigneeEmail.isEmpty ? '' : ' | ${meeting.assigneeEmail}'}${meeting.followUpDate == null ? '' : ' | Due ${meeting.followUpDate!.toLocal()}'}',
                if (supplierCommitment.isNotEmpty)
                  'Supplier: $supplierCommitment',
                if (ourCommitment.isNotEmpty) 'Us: $ourCommitment',
              ];
              return Card(
                  child: ListTile(
                leading: Icon(
                    meeting.completed ? Icons.task_alt : Icons.schedule,
                    color:
                        meeting.completed ? AppColors.teal : AppColors.amber),
                title: Text(meeting.outcome),
                subtitle: Text(lines.join('\n'),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: lines.length > 1,
                trailing: meeting.completed
                    ? null
                    : IconButton(
                        tooltip: 'Mark complete',
                        onPressed: () => _complete(meeting),
                        icon: const Icon(Icons.check_circle_outline)),
              ));
            },
          );
        },
      );

  Widget _filesTab() => FutureBuilder<List<Attachment>>(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data ?? const <Attachment>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (files.isEmpty) {
            return _empty(
                'No files',
                'Add a photo or document from the supplier capture screen.',
                Icons.attach_file_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final file = files[index];
              final annotationCount = (() {
                try {
                  return (jsonDecode(file.annotationsJson) as List).length;
                } catch (_) {
                  return 0;
                }
              })();
              return Card(
                  child: ListTile(
                leading: Icon(file.kind == 'image'
                    ? Icons.photo_outlined
                    : file.kind == 'video'
                        ? Icons.videocam_outlined
                        : file.kind == 'pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.attach_file_outlined),
                title: Text(file.note.isEmpty ? file.kind : file.note),
                subtitle: Text(
                    '${annotationCount == 0 ? '' : '$annotationCount photo note${annotationCount == 1 ? '' : 's'} | '}${file.path}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ));
            },
          );
        },
      );

  Widget _verificationChip() {
    final status = _verification()['status'] as String? ?? 'Unverified';
    final color = switch (status) {
      'Approved' => AppColors.teal,
      'Blocked' => AppColors.danger,
      'In review' => AppColors.amber,
      _ => AppColors.muted,
    };
    final icon = switch (status) {
      'Approved' => Icons.verified_outlined,
      'Blocked' => Icons.block_outlined,
      'In review' => Icons.pending_outlined,
      _ => Icons.shield_outlined,
    };
    return InfoChip(label: status, icon: icon, color: color);
  }

  Widget _verificationTab() {
    final data = _verification();
    final certificates = _certificates(data);
    final status = data['status'] as String? ?? 'Unverified';
    final risks = <String>[
      if (_verificationFlag(data, 'payment_risk')) 'Payment risk',
      if (_verificationFlag(data, 'communication_risk')) 'Communication risk',
      if (_verificationFlag(data, 'factory_audit_required'))
        'Factory audit required',
      if (_verificationFlag(data, 'quality_risk')) 'Quality risk',
      if (_verificationFlag(data, 'ip_risk')) 'IP risk',
      if (_verificationFlag(data, 'compliance_risk')) 'Compliance risk',
      if (_verificationFlag(data, 'trading_company_risk'))
        'Trading-company risk',
      if (_verificationFlag(data, 'capacity_risk')) 'Capacity risk',
    ];
    final details = <(String, String)>[
      ('Supplier type', data['company_type'] as String? ?? ''),
      ('Years exporting', data['years_exporting'] as String? ?? ''),
      ('Export markets', data['export_markets'] as String? ?? ''),
      ('Sample', data['sample_status'] as String? ?? ''),
    ]
        .where((detail) =>
            detail.$2.isNotEmpty &&
            detail.$2 != 'Not verified' &&
            detail.$2 != 'Not requested')
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionPanel(
          title: 'Supplier verification',
          subtitle:
              'Validate supplier capability and document procurement risk.',
          trailing: IconButton(
            tooltip: 'Edit verification',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editVerification,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _verificationChip(),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: details
                      .map((detail) =>
                          InfoChip(label: '${detail.$1}: ${detail.$2}'))
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InfoChip(
                    label: _verificationFlag(data, 'certificates_verified')
                        ? 'Certificates verified'
                        : 'Certificates not verified',
                    icon: Icons.workspace_premium_outlined,
                    color: _verificationFlag(data, 'certificates_verified')
                        ? AppColors.teal
                        : AppColors.amber,
                  ),
                  ...risks.map((risk) => InfoChip(
                      label: risk,
                      icon: Icons.warning_amber_outlined,
                      color: AppColors.danger)),
                ],
              ),
              if ((data['notes'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(data['notes'] as String),
              ],
              const SizedBox(height: 12),
              Builder(
                builder: (tabContext) => OutlinedButton.icon(
                  onPressed: () =>
                      DefaultTabController.of(tabContext).animateTo(4),
                  icon: const Icon(Icons.attach_file_outlined),
                  label: const Text('View certificate and audit proof'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionPanel(
          title: 'Certificate register',
          subtitle: certificates.isEmpty
              ? 'Record compliance documents and expiry dates.'
              : '${certificates.length} certificate${certificates.length == 1 ? '' : 's'} recorded',
          trailing: IconButton(
            tooltip: 'Add certificate',
            onPressed: _editCertificate,
            icon: const Icon(Icons.add_circle_outline),
          ),
          child: certificates.isEmpty
              ? OutlinedButton.icon(
                  onPressed: _editCertificate,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Add certificate'),
                )
              : Column(
                  children: certificates.asMap().entries.map((entry) {
                    final certificate = entry.value;
                    final expiry = DateTime.tryParse(
                        certificate['expiry'] as String? ?? '');
                    final expired = expiry != null &&
                        expiry.isBefore(
                            DateTime.now().subtract(const Duration(days: 1)));
                    final status = certificate['verified'] == true
                        ? 'Verified'
                        : 'Not verified';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          certificate['verified'] == true
                              ? Icons.verified_outlined
                              : Icons.pending_outlined,
                          color: certificate['verified'] == true
                              ? AppColors.teal
                              : AppColors.amber,
                        ),
                        title: Text(
                            certificate['type'] as String? ?? 'Certificate'),
                        subtitle: Text([
                          status,
                          if ((certificate['number'] as String? ?? '')
                              .isNotEmpty)
                            certificate['number'] as String,
                          if (expiry != null)
                            '${expired ? 'Expired' : 'Expires'} ${expiry.year.toString().padLeft(4, '0')}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}',
                          '${(certificate['checks'] as List? ?? const []).length}/4 checks',
                        ].join(' | ')),
                        isThreeLine:
                            (certificate['issuer'] as String? ?? '').isNotEmpty,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Certificate actions',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editCertificate(certificate, entry.key);
                            } else {
                              _deleteCertificate(entry.key);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (status == 'Unverified') ...[
          const SizedBox(height: 16),
          SectionPanel(
            title: 'Next step',
            child: FilledButton.icon(
              onPressed: _editVerification,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Start verification'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _samplesTab() => FutureBuilder<List<Sample>>(
        future: _samples,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final samples = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: _openSampleDialog,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Track a sample'),
              ),
              const SizedBox(height: 16),
              if (samples.isEmpty)
                const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No samples tracked',
                  message:
                      'Track sample requests, delivery, testing, and approval for this supplier.',
                )
              else
                ...samples.map((sample) {
                  final overdue = sample.expectedAt != null &&
                      sample.expectedAt!.isBefore(DateTime.now()) &&
                      !['Received', 'Approved', 'Rejected']
                          .contains(sample.status);
                  final color = overdue
                      ? AppColors.danger
                      : sample.status == 'Approved'
                          ? AppColors.teal
                          : sample.status == 'Rejected'
                              ? AppColors.danger
                              : AppColors.amber;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: Icon(
                            overdue
                                ? Icons.warning_amber_outlined
                                : Icons.inventory_2_outlined,
                            color: color),
                        title: Text(sample.status,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text([
                          if (sample.expectedAt != null)
                            '${overdue ? 'Late' : 'Expected'} ${sample.expectedAt!.toLocal().toString().substring(0, 10)}',
                          if (sample.courier.isNotEmpty) sample.courier,
                          if (sample.trackingNumber.isNotEmpty)
                            'Tracking ${sample.trackingNumber}',
                          if (sample.assigneeEmail.isNotEmpty)
                            'Owner ${sample.assigneeEmail}',
                          if (sample.testNotes.isNotEmpty) sample.testNotes,
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Update sample',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openSampleDialog(sample),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      );

  Widget _purchaseTab() => FutureBuilder<List<_PurchaseReadinessItem>>(
        future: _loadPurchaseItems(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionPanel(
                title: 'Purchase readiness',
                subtitle:
                    'Move only fully verified products into procurement handover.',
                trailing: IconButton(
                  tooltip: 'Share purchase handover',
                  icon: const Icon(Icons.ios_share_outlined),
                  onPressed: _sharePurchaseReady,
                ),
                child: items.isEmpty
                    ? const Text(
                        'Add products before preparing a purchase handover.')
                    : Column(
                        children: items.map((item) {
                          final plan = _purchasePlan(item.product);
                          final status = plan['status'] as String? ?? 'Draft';
                          final ready = item.blockers.isEmpty &&
                              status == 'Ready to order';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFBFD),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text(item.product.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800))),
                                      InfoChip(
                                          label: ready ? 'Ready' : status,
                                          color: ready
                                              ? AppColors.teal
                                              : AppColors.amber),
                                    ]),
                                    const SizedBox(height: 8),
                                    Text(
                                        'MOQ ${item.product.moq ?? '-'} | ${item.product.quotedPrice == null ? 'No quote' : '${item.product.quotedPrice} ${item.product.priceCurrency}'} | ${item.product.leadTime.isEmpty ? 'No lead time' : item.product.leadTime}'),
                                    if (item.blockers.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: item.blockers
                                              .map((blocker) => InfoChip(
                                                  label: blocker,
                                                  icon: Icons
                                                      .warning_amber_outlined,
                                                  color: AppColors.danger))
                                              .toList()),
                                    ],
                                    if (plan['target_quantity'] != null ||
                                        plan['estimated_order_value'] !=
                                            null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                          'Target ${plan['target_quantity'] ?? '-'} | Est. value ${plan['estimated_order_value'] ?? '-'}'),
                                    ],
                                    if ((plan['po_number'] as String? ?? '')
                                            .isNotEmpty ||
                                        (plan['production_status'] as String? ??
                                                '') !=
                                            'Not started' ||
                                        (plan['delivery_status'] as String? ??
                                                '') !=
                                            'Not booked') ...[
                                      const SizedBox(height: 8),
                                      Text(
                                          'PO ${plan['po_number'] ?? 'Draft'} | Production ${plan['production_status'] ?? 'Not started'} | Delivery ${plan['delivery_status'] ?? 'Not booked'}'),
                                    ],
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                          onPressed: () =>
                                              _editPurchasePlan(item),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text(
                                              'PO draft & handover')),
                                    ),
                                  ]),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          );
        },
      );

  Widget _scorecard(Exhibitor supplier) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Supplier scorecard',
            subtitle: 'Scores recorded during supplier review.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                    label: 'Rating ${supplier.rating}/5',
                    icon: Icons.star,
                    color: AppColors.amber),
                InfoChip(
                    label: 'Quality ${supplier.qualityScore}',
                    icon: Icons.verified_outlined),
                InfoChip(
                    label: 'Response ${supplier.responseSpeedScore}',
                    icon: Icons.speed_outlined,
                    color: AppColors.teal),
                InfoChip(
                    label: 'Trust ${supplier.trustScore}',
                    icon: Icons.handshake_outlined,
                    color: const Color(0xFF6B4E9B)),
                InfoChip(
                    label: 'MOQ fit ${supplier.moqFitScore}',
                    icon: Icons.inventory_2_outlined),
                InfoChip(
                    label: 'Reliability ${supplier.reliabilityScore}',
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF2F855A)),
              ],
            ),
          ),
        ],
      );
}

class _PurchaseReadinessItem {
  final Product product;
  final List<String> blockers;

  const _PurchaseReadinessItem({required this.product, required this.blockers});
}
