import 'dart:convert';
import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auto_sync_service.dart';
import '../data/camera_capture_service.dart';
import '../data/database.dart';
import '../data/meeting_ai_service.dart';
import '../data/photo_similarity_service.dart';
import '../data/reminder_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import '../widgets/voice_note_field.dart';
import 'procurement_workspace_screen.dart';
import 'settings_screen.dart';
import 'dashboard_screen.dart';
import 'catalogue_vault_screen.dart';
import 'field_product_capture_screen.dart';
import 'field_work_screen.dart';
import 'followup_screen.dart';
import 'sync_status_screen.dart';

class FieldOperationsScreen extends StatefulWidget {
  const FieldOperationsScreen({super.key, this.onScanCard});

  final VoidCallback? onScanCard;

  @override
  State<FieldOperationsScreen> createState() => _FieldOperationsScreenState();
}

class _FieldOperationsScreenState extends State<FieldOperationsScreen> {
  final _db = TradeDatabase.instance;
  late Future<_FieldData> _data = _load();

  Future<_FieldData> _load() async => _FieldData(
        await _db.getTrips(),
        await _db.getExhibitors(null),
        await _db.getMeetings(),
        await _db.getSamples(),
      );

  void _refresh() => setState(() => _data = _load());

  Future<T?> _pick<T>(String title, List<T> items, String Function(T) label) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing to select',
                message: 'Create the related record first.',
              ),
            ...items.map((item) => ListTile(
                  title: Text(label(item)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, item),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecorder(_FieldData data) async {
    final supplier =
        await _pick('Record meeting for', data.suppliers, (e) => e.name);
    if (supplier == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingRecorderScreen(supplier: supplier),
        ));
    _refresh();
  }

  Future<void> _quickProduct(_FieldData data) async {
    final supplier =
        await _pick('Add product for', data.suppliers, (e) => e.name);
    if (supplier == null || !mounted || supplier.id == null) return;
    final scope = await TeamWorkspaceService().scopeKey();
    if (!mounted) return;
    _open(FieldProductCaptureScreen(
      scope: scope,
      supplierId: supplier.id!,
      supplierName: supplier.name,
    ));
  }

  Future<void> _visitChecklist(_FieldData data) async {
    final supplier = await _pick(
        'Complete visit checklist for', data.suppliers, (e) => e.name);
    if (supplier == null || !mounted || supplier.id == null) return;

    var boothVisited = true;
    var samplesCollected = false;
    var brochureReceived = false;
    var followUpRequired = true;
    var action = 'Call';
    var dueAt = DateTime.now().add(const Duration(days: 1));
    final notes = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Visit checklist: ${supplier.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Booth visited'),
                value: boothVisited,
                onChanged: (value) => setDialogState(() => boothVisited = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Samples collected'),
                value: samplesCollected,
                onChanged: (value) =>
                    setDialogState(() => samplesCollected = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Brochure received'),
                value: brochureReceived,
                onChanged: (value) =>
                    setDialogState(() => brochureReceived = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Follow-up required'),
                value: followUpRequired,
                onChanged: (value) =>
                    setDialogState(() => followUpRequired = value),
              ),
              if (followUpRequired) ...[
                DropdownButtonFormField<String>(
                  initialValue: action,
                  decoration: const InputDecoration(labelText: 'Next action'),
                  items: const ['Call', 'Email', 'Sample request', 'Quotation deadline']
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => action = value!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder date'),
                  subtitle: Text(_date(dueAt)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: dueAt,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (value != null) setDialogState(() => dueAt = value);
                  },
                ),
              ],
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Visit notes',
                  hintText: 'Key discussion points, samples, and commitments',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save checklist')),
          ],
        ),
      ),
    );
    if (save != true) return;
    final checklist = [
      'Booth visited: ${boothVisited ? 'Yes' : 'No'}',
      'Samples collected: ${samplesCollected ? 'Yes' : 'No'}',
      'Brochure received: ${brochureReceived ? 'Yes' : 'No'}',
      'Follow-up required: ${followUpRequired ? 'Yes' : 'No'}',
      if (notes.text.trim().isNotEmpty) notes.text.trim(),
    ].join('\n');
    final meetingId = await _db.insert('meetings', {
      'exhibitor_id': supplier.id!,
      'meeting_date': DateTime.now().toIso8601String(),
      'follow_up_date': followUpRequired ? dueAt.toIso8601String() : null,
      'outcome': followUpRequired ? action : 'Visit completed',
      'priority': followUpRequired ? 'Medium' : 'Low',
      'notes': checklist,
    });
    if (followUpRequired) {
      await ReminderService.scheduleFollowUp(
        id: meetingId,
        title: '$action: ${supplier.name}',
        body: checklist.replaceAll('\n', ' | '),
        at: DateTime(dueAt.year, dueAt.month, dueAt.day, 9),
      );
    }
    await _db.logAudit('Completed visit checklist', supplier.name);
    _refresh();
  }

  void _openTripDashboard() => _open(DashboardScreen(
        onCapture: widget.onScanCard,
        onScanCard: widget.onScanCard,
        onSync: () => _open(const SyncStatusScreen()),
        onFollowUps: () => _open(const FollowUpScreen()),
      ));

  Future<void> _addCalendarEvent(_FieldData data) async {
    final meetings =
        data.meetings.where((m) => m.followUpDate != null).toList();
    final meeting = await _pick('Add follow-up to calendar', meetings, (m) {
      final supplier =
          data.suppliers.where((e) => e.id == m.exhibitorId).firstOrNull;
      return '${supplier?.name ?? 'Supplier'} - ${_date(m.followUpDate!)}';
    });
    if (meeting == null) return;
    final supplier =
        data.suppliers.where((e) => e.id == meeting.exhibitorId).firstOrNull;
    final start = meeting.followUpDate!;
    await Add2Calendar.addEvent2Cal(Event(
      title: 'Supplier follow-up: ${supplier?.name ?? 'Supplier'}',
      description: meeting.notes,
      location: supplier?.booth ?? '',
      startDate: start,
      endDate: start.add(const Duration(minutes: 30)),
    ));
  }

  Future<List<Exhibitor>> _pickRecipients(List<Exhibitor> suppliers) async {
    final chosen = <int>{};
    return await showModalBottomSheet<List<Exhibitor>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) =>
              StatefulBuilder(builder: (context, setSheetState) {
            return SafeArea(
                child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Expanded(
                        child: Text('RFQ recipients',
                            style: Theme.of(context).textTheme.titleLarge)),
                    FilledButton(
                      onPressed: chosen.isEmpty
                          ? null
                          : () => Navigator.pop(
                                context,
                                suppliers
                                    .where((e) => chosen.contains(e.id))
                                    .toList(),
                              ),
                      child: Text('Use ${chosen.length}'),
                    ),
                  ]),
                ),
                const Divider(),
                Expanded(
                    child: ListView(
                        children: suppliers
                            .map((supplier) => CheckboxListTile(
                                  value: chosen.contains(supplier.id),
                                  title: Text(supplier.name),
                                  subtitle: Text([
                                    supplier.booth,
                                    supplier.category
                                  ].where((v) => v.isNotEmpty).join(' | ')),
                                  onChanged: (value) => setSheetState(() {
                                    if (value == true) {
                                      chosen.add(supplier.id!);
                                    } else {
                                      chosen.remove(supplier.id);
                                    }
                                  }),
                                ))
                            .toList())),
              ]),
            ));
          }),
        ) ??
        <Exhibitor>[];
  }

  Future<void> _createRfq(_FieldData data) async {
    final recipients = await _pickRecipients(data.suppliers);
    if (recipients.isEmpty || !mounted) return;
    final title = TextEditingController();
    final requirements = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('Create RFQ'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'RFQ title')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: requirements,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                          labelText:
                              'Product, specification, quantity, target terms')),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Response due'),
                    subtitle: Text(_date(due)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final value = await showDatePicker(
                          context: context,
                          initialDate: due,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)));
                      if (value != null) setDialogState(() => due = value);
                    },
                  ),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Create & share')),
                ],
              ),
            ));
    if (save != true || title.text.trim().isEmpty) return;
    await _db.insert('rfqs', {
      'title': title.text.trim(),
      'requirements': requirements.text.trim(),
      'recipients_json': jsonEncode(
          recipients.map((e) => {'name': e.name, 'booth': e.booth}).toList()),
      'products_json': '[]',
      'status': 'Sent',
      'due_at': due.toIso8601String(),
    });
    final text = '''REQUEST FOR QUOTATION
${title.text.trim()}

${requirements.text.trim()}

Please respond by ${_date(due)} with unit price, MOQ, lead time, payment terms, packing details, sample cost, and quote validity.''';
    await SharePlus.instance
        .share(ShareParams(text: text, subject: title.text.trim()));
    await _db.logAudit('Created RFQ',
        '${title.text.trim()} for ${recipients.length} suppliers');
    _refresh();
  }

  Future<void> _manageRfqs(_FieldData data) async {
    final rows = await _db.queryAll('rfqs', orderBy: 'created_at DESC');
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                    child: Text('RFQ register',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _createRfq(data);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New RFQ')),
              ]),
            ),
            const Divider(),
            Expanded(
                child: rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.request_quote_outlined,
                        title: 'No RFQs yet',
                        message:
                            'Create one request and share it with selected suppliers.')
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: rows.map((row) {
                          final recipients =
                              (jsonDecode(row['recipients_json'] as String)
                                      as List)
                                  .length;
                          return Card(
                              child: ListTile(
                            leading: const Icon(Icons.request_quote_outlined),
                            title: Text(row['title']),
                            subtitle: Text(
                                '${row['status']} | $recipients suppliers | Due ${row['due_at']?.toString().split('T').first ?? '-'}'),
                            trailing: IconButton(
                                tooltip: 'Share again',
                                icon: const Icon(Icons.ios_share_outlined),
                                onPressed: () {
                                  SharePlus.instance.share(ShareParams(
                                      text:
                                          '${row['title']}\n\n${row['requirements']}\n\nResponse due: ${row['due_at']?.toString().split('T').first ?? '-'}'));
                                }),
                          ));
                        }).toList())),
          ]),
        ),
      ),
    );
  }

  Future<void> _manageExpenses(_FieldData data) async {
    final rows = await _db.queryAll('expenses', orderBy: 'incurred_at DESC');
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                    child: Text('Fair expenses',
                        style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _addExpense(data);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add')),
              ])),
          const Divider(),
          Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No expenses yet',
                      message:
                          'Record fair spending and attach receipt photos.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: rows
                          .map((row) => Card(
                                  child: ListTile(
                                leading:
                                    const Icon(Icons.receipt_long_outlined),
                                title: Text(
                                    '${row['amount']} ${row['currency']} - ${row['category']}'),
                                subtitle: Text(
                                    '${row['note']}\n${row['incurred_at'].toString().split('T').first}'),
                                isThreeLine: true,
                              )))
                          .toList())),
        ]),
      )),
    );
  }

  Future<void> _supplierComments(_FieldData data) async {
    final supplier =
        await _pick('Team notes for supplier', data.suppliers, (e) => e.name);
    if (supplier == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupplierCommentsScreen(supplier: supplier),
        ));
  }

  Future<void> _diligence(_FieldData data) async {
    final supplier =
        await _pick('Check supplier', data.suppliers, (e) => e.name);
    if (supplier == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DueDiligenceScreen(supplier: supplier),
        ));
  }

  Future<void> _sampleQr(_FieldData data) async {
    final sample = await _pick('Create sample label', data.samples, (s) {
      final supplier =
          data.suppliers.where((e) => e.id == s.exhibitorId).firstOrNull;
      return '${supplier?.name ?? 'Supplier'} - ${s.status}';
    });
    if (sample == null || !mounted) return;
    final supplier =
        data.suppliers.where((e) => e.id == sample.exhibitorId).firstOrNull;
    final code =
        'CFC-SAMPLE:${sample.id}:${sample.exhibitorId}:${sample.productId ?? 0}';
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(supplier?.name ?? 'Sample label'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                QrImageView(data: code, size: 220),
                const SizedBox(height: 10),
                Text('Sample #${sample.id} | ${sample.status}',
                    textAlign: TextAlign.center),
                if (sample.trackingNumber.isNotEmpty)
                  Text(sample.trackingNumber),
              ]),
              actions: [
                TextButton(
                    onPressed: () =>
                        SharePlus.instance.share(ShareParams(text: code)),
                    child: const Text('Share code')),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done')),
              ],
            ));
  }

  Future<void> _addExpense(_FieldData data) async {
    final trip = await _pick('Expense trip', data.trips, (e) => e.name);
    if (trip == null || !mounted) return;
    final amount = TextEditingController();
    final note = TextEditingController();
    var category = 'Transport';
    var currency = 'CNY';
    XFile? receipt;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('Add fair expense'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: category,
                      items: [
                        'Transport',
                        'Hotel',
                        'Meals',
                        'Samples',
                        'Freight',
                        'Printing',
                        'Other'
                      ]
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => category = v!,
                      decoration: const InputDecoration(labelText: 'Category')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: amount,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Amount'))),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                            initialValue: currency,
                            items: ['CNY', 'USD', 'AED', 'EUR']
                                .map((v) =>
                                    DropdownMenuItem(value: v, child: Text(v)))
                                .toList(),
                            onChanged: (v) => currency = v!,
                            decoration:
                                const InputDecoration(labelText: 'Currency'))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: note,
                      decoration:
                          const InputDecoration(labelText: 'Merchant or note')),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: Icon(receipt == null
                        ? Icons.receipt_long_outlined
                        : Icons.check_circle_outline),
                    label: Text(receipt == null
                        ? 'Photograph receipt'
                        : 'Receipt ready'),
                    onPressed: () async {
                      final picked = await CameraCaptureService.capture(() =>
                          ImagePicker().pickImage(
                              source: ImageSource.camera, imageQuality: 82));
                      if (picked != null) {
                        setDialogState(() => receipt = picked);
                      }
                    },
                  ),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save')),
                ],
              ),
            ));
    final value = double.tryParse(amount.text.trim());
    if (save != true || value == null || value <= 0) return;
    final id = await _db.insert('expenses', {
      'trip_id': trip.id,
      'category': category,
      'amount': value,
      'currency': currency,
      'note': note.text.trim(),
      'incurred_at': DateTime.now().toIso8601String(),
    });
    if (receipt != null) {
      final root = await getApplicationDocumentsDirectory();
      final target = File(
          '${root.path}/expense_receipts/${await TeamWorkspaceService().scopeKey()}/$id.jpg');
      await target.parent.create(recursive: true);
      await File(receipt!.path).copy(target.path);
      await _db.addAttachment(Attachment(
          ownerType: 'expense',
          ownerId: id,
          kind: 'image',
          path: target.path,
          note: 'Receipt - $category',
          createdAt: DateTime.now()));
    }
    await _db.logAudit(
        'Added expense', '$category $value $currency for ${trip.name}');
    _refresh();
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
          .then((_) => _refresh());

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Field operations')),
        body: FutureBuilder<_FieldData>(
            future: _data,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              return ListView(padding: const EdgeInsets.all(16), children: [
                const _FieldSectionHeader('TODAY AT THE FAIR'),
                _tile(
                    'Trip dashboard',
                    'Today\'s visits, pending follow-ups, and field progress',
                    Icons.dashboard_outlined,
                    _openTripDashboard),
                _tile(
                    'Booth visits & checklist',
                    'Plan visits, record booth outcomes, samples, brochures, and next actions',
                    Icons.fact_check_outlined,
                    () => _open(const FieldWorkScreen())),
                _tile(
                    'Close visit & follow-up',
                    'Save the visit outcome, samples, brochures, and next action',
                    Icons.checklist_outlined,
                    () => _visitChecklist(data)),
                _tile(
                    'Follow-up reminders',
                    'Call, email, sample request, and quotation deadlines',
                    Icons.event_available_outlined,
                    () => _open(const FollowUpScreen())),
                _tile(
                    'Offline sync center',
                    'Review pending records, failed uploads, retries, and last sync time',
                    Icons.sync_problem_outlined,
                    () => _open(const SyncStatusScreen())),
                const SizedBox(height: 24),
                const _FieldSectionHeader('AUTOMATE & COLLABORATE'),
                _tile(
                    'Automatic team sync',
                    'Sync on resume, connection recovery, and live team changes',
                    Icons.sync_outlined,
                    () => _open(const SettingsScreen())),
                _tile(
                    'Team update alerts',
                    'Local notifications when live cloud changes download',
                    Icons.notifications_active_outlined,
                    () => AutoSyncService.instance.syncIfPossible()),
                _tile(
                    'Team notes & mentions',
                    'Discuss a supplier and mention teammates',
                    Icons.alternate_email,
                    () => _supplierComments(data)),
                _tile(
                    'Protected editing',
                    'Supplier pages warn when a teammate is editing',
                    Icons.lock_clock_outlined,
                    () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Open a supplier to use protected editing.')))),
                const SizedBox(height: 24),
                const _FieldSectionHeader('CAPTURE & COMMUNICATE'),
                _tile(
                    'Business-card scan & quality review',
                    'Check crop coverage before saving and retake unclear cards',
                    Icons.badge_outlined,
                    widget.onScanCard ??
                        () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Card scanning is unavailable.')))),
                _tile(
                    'Quick product capture',
                    'Photo, product name, MOQ, unit price, lead time, and notes',
                    Icons.inventory_2_outlined,
                    () => _quickProduct(data)),
                _tile(
                    'Meeting recorder & minutes',
                    'Record audio and create structured meeting minutes',
                    Icons.mic_none_outlined,
                    () => _openRecorder(data)),
                _tile(
                    'Conversation translator',
                    'Useful English and Chinese fair phrases with speech',
                    Icons.translate_outlined,
                    () => _open(const ConversationTranslatorScreen())),
                _tile(
                    'Catalogue & price-list scan',
                    'Extract text from a catalogue photo and link it to a supplier',
                    Icons.document_scanner_outlined,
                    () => _open(
                        CatalogueScannerScreen(suppliers: data.suppliers))),
                _tile(
                    'Supplier catalogue vault',
                    'Archive supplier PDFs, links, QR catalogues, and hard-copy brochures for permanent access',
                    Icons.inventory_2_outlined,
                    () => _open(CatalogueVaultScreen(suppliers: data.suppliers))),
                _tile(
                    'Phone calendar',
                    'Send a supplier follow-up to the device calendar',
                    Icons.calendar_month_outlined,
                    () => _addCalendarEvent(data)),
                _tile(
                    'Canton Fair directory import',
                    'Import exhibitor CSV data into a selected trip',
                    Icons.table_view_outlined,
                    () =>
                        _open(const ProcurementWorkspaceScreen(initialTab: 2))),
                const SizedBox(height: 24),
                const _FieldSectionHeader('SOURCE & VERIFY'),
                _tile(
                    'Duplicate review',
                    'Check visually similar product photos before adding another record',
                    Icons.content_copy_outlined,
                    () => _open(PhotoMatchScreen(suppliers: data.suppliers))),
                _tile(
                    'RFQ builder',
                    'Create one request and share it with selected suppliers',
                    Icons.request_quote_outlined,
                    () => _manageRfqs(data)),
                _tile(
                    'Product photo match',
                    'Find visually similar product photos across suppliers',
                    Icons.image_search_outlined,
                    () => _open(PhotoMatchScreen(suppliers: data.suppliers))),
                _tile(
                    'Sample QR labels',
                    'Create a traceable QR label for each sample',
                    Icons.qr_code_2_outlined,
                    () => _sampleQr(data)),
                _tile(
                    'Supplier due diligence',
                    'Record registration, sanctions, IP, web, and reference checks',
                    Icons.fact_check_outlined,
                    () => _diligence(data)),
                const SizedBox(height: 24),
                const _FieldSectionHeader('CONTROL & RECOVER'),
                _tile(
                    'Recycle bin & versions',
                    'Restore deleted records or an earlier saved version',
                    Icons.restore_outlined,
                    () => _open(const RecoveryScreen())),
                _tile(
                    'Fair expenses & receipts',
                    'Track trip spending and photograph receipts',
                    Icons.receipt_long_outlined,
                    () => _manageExpenses(data)),
              ]);
            }),
      );

  Widget _tile(
          String title, String subtitle, IconData icon, VoidCallback onTap) =>
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: Theme.of(context).colorScheme.onSecondaryContainer)),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class MeetingRecorderScreen extends StatefulWidget {
  final Exhibitor supplier;
  const MeetingRecorderScreen({super.key, required this.supplier});

  @override
  State<MeetingRecorderScreen> createState() => _MeetingRecorderScreenState();
}

class _MeetingRecorderScreenState extends State<MeetingRecorderScreen> {
  final _recorder = AudioRecorder();
  final _notes = TextEditingController();
  bool _recording = false;
  String? _path;

  @override
  void dispose() {
    _recorder.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _path = path;
        });
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final root = await getApplicationDocumentsDirectory();
    final file =
        '${root.path}/meeting_audio/${await TeamWorkspaceService().scopeKey()}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await Directory(File(file).parent.path).create(recursive: true);
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: file);
    if (mounted) setState(() => _recording = true);
  }

  String _minutes(String text) {
    final lines = text
        .split(RegExp(r'[\n.!?]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final commercial = lines.where((e) =>
        RegExp(r'price|moq|payment|lead|delivery|sample', caseSensitive: false)
            .hasMatch(e));
    final actions = lines.where((e) =>
        RegExp(r'will|send|confirm|follow|next|due|agree', caseSensitive: false)
            .hasMatch(e));
    return [
      'MEETING MINUTES',
      'Supplier: ${widget.supplier.name}',
      'Date: ${DateTime.now().toLocal()}',
      '',
      'Discussion',
      ...(lines.isEmpty
          ? ['- Add meeting notes before generating minutes.']
          : lines.map((e) => '- $e')),
      '',
      'Commercial points',
      ...(commercial.isEmpty
          ? ['- Not recorded']
          : commercial.map((e) => '- $e')),
      '',
      'Actions and commitments',
      ...(actions.isEmpty
          ? ['- Confirm next action']
          : actions.map((e) => '- $e')),
    ].join('\n');
  }

  Future<void> _save() async {
    if (_recording) await _toggle();
    var minutes = _minutes(_notes.text.trim());
    if (_notes.text.trim().isNotEmpty) {
      try {
        minutes = await MeetingAiService.createMinutes(
            supplier: widget.supplier.name, notes: _notes.text.trim());
      } catch (_) {
        // The deterministic local summary keeps field work available offline.
      }
    }
    await TradeDatabase.instance.insert('meetings', {
      'exhibitor_id': widget.supplier.id,
      'meeting_date': DateTime.now().toIso8601String(),
      'outcome': 'Meeting recorded',
      'priority': 'Medium',
      'notes': minutes,
    });
    if (_path != null) {
      await TradeDatabase.instance.addAttachment(Attachment(
          ownerType: 'exhibitor',
          ownerId: widget.supplier.id!,
          kind: 'audio',
          path: _path!,
          note: 'Meeting audio',
          createdAt: DateTime.now()));
    }
    await TradeDatabase.instance
        .logAudit('Recorded meeting', widget.supplier.name);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meeting recorder')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(widget.supplier.name,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text(
              'Record the discussion, then add short notes so the app can structure the minutes.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: _recording ? AppColors.danger : null,
                minimumSize: const Size.fromHeight(56)),
            onPressed: _toggle,
            icon: Icon(_recording ? Icons.stop : Icons.mic),
            label: Text(_recording
                ? 'Stop recording'
                : _path == null
                    ? 'Start recording'
                    : 'Record again'),
          ),
          if (_path != null)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Audio ready to save.')),
          const SizedBox(height: 20),
          TextField(
              controller: _notes,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                  labelText: 'Discussion notes',
                  hintText: 'Price, MOQ, lead time, promises, next action...')),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Save audio & structured minutes')),
        ]),
      );
}

class ConversationTranslatorScreen extends StatefulWidget {
  const ConversationTranslatorScreen({super.key});
  @override
  State<ConversationTranslatorScreen> createState() =>
      _ConversationTranslatorScreenState();
}

class _ConversationTranslatorScreenState
    extends State<ConversationTranslatorScreen> {
  final _tts = FlutterTts();
  final _search = TextEditingController();
  bool _englishFirst = true;
  bool _translating = false;
  String _translated = '';
  final _phrases = const <(String, String)>[
    ('What is your minimum order quantity?', '你们的最小起订量是多少？'),
    ('What is your best price?', '你们的最优惠价格是多少？'),
    ('How long is the production lead time?', '生产交货期是多长时间？'),
    ('Can you provide a sample?', '你们可以提供样品吗？'),
    ('Do you support OEM or ODM?', '你们支持OEM或ODM吗？'),
    ('Which certifications do you have?', '你们有哪些认证？'),
    ('Please send the catalogue and price list.', '请发送产品目录和价格表。'),
    ('Can I visit your factory?', '我可以参观你们的工厂吗？'),
    ('What are your payment terms?', '你们的付款条件是什么？'),
    ('Please write the details here.', '请把详细信息写在这里。'),
  ];

  @override
  void dispose() {
    _tts.stop();
    _search.dispose();
    super.dispose();
  }

  Future<void> _speak(String value, String language) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(.42);
    await _tts.speak(value);
  }

  Future<void> _translate() async {
    final text = _search.text.trim();
    if (text.isEmpty || _translating) return;
    setState(() => _translating = true);
    final source =
        _englishFirst ? TranslateLanguage.english : TranslateLanguage.chinese;
    final target =
        _englishFirst ? TranslateLanguage.chinese : TranslateLanguage.english;
    final manager = OnDeviceTranslatorModelManager();
    OnDeviceTranslator? translator;
    try {
      for (final language in [source, target]) {
        if (!await manager.isModelDownloaded(language.bcpCode)) {
          await manager.downloadModel(language.bcpCode);
        }
      }
      translator =
          OnDeviceTranslator(sourceLanguage: source, targetLanguage: target);
      final result = await translator.translateText(text);
      if (mounted) setState(() => _translated = result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Translation model unavailable. The fair phrasebook still works. $error')));
      }
    } finally {
      await translator?.close();
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final visible = _phrases
        .where((p) => '${p.$1} ${p.$2}'.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation translator')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('English to Chinese')),
            ButtonSegment(value: false, label: Text('Chinese to English')),
          ],
          selected: {_englishFirst},
          onSelectionChanged: (value) => setState(() {
            _englishFirst = value.first;
            _translated = '';
          }),
        ),
        const SizedBox(height: 12),
        VoiceNoteField(
            controller: _search,
            label: _englishFirst ? 'Speak or type English' : 'Type Chinese',
            maxLines: 2),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
              onPressed: _translating ? null : _translate,
              icon: const Icon(Icons.translate),
              label: Text(_translating ? 'Translating...' : 'Translate')),
        ),
        if (_translated.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                        child: Text(_translated,
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        tooltip: 'Speak translation',
                        onPressed: () => _speak(
                            _translated, _englishFirst ? 'zh-CN' : 'en-US'),
                        icon: const Icon(Icons.volume_up_outlined)),
                  ]))),
        ],
        const SizedBox(height: 14),
        ...visible.map((phrase) => Card(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(phrase.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          tooltip: 'Speak English',
                          onPressed: () => _speak(phrase.$1, 'en-US'),
                          icon: const Icon(Icons.volume_up_outlined))
                    ]),
                    const Divider(),
                    Row(children: [
                      Expanded(
                          child: Text(phrase.$2,
                              style: Theme.of(context).textTheme.titleMedium)),
                      IconButton(
                          tooltip: 'Speak Chinese',
                          onPressed: () => _speak(phrase.$2, 'zh-CN'),
                          icon: const Icon(Icons.volume_up_outlined))
                    ]),
                  ]),
            ))),
      ]),
    );
  }
}

class CatalogueScannerScreen extends StatefulWidget {
  final List<Exhibitor> suppliers;
  const CatalogueScannerScreen({super.key, required this.suppliers});
  @override
  State<CatalogueScannerScreen> createState() => _CatalogueScannerScreenState();
}

class _CatalogueScannerScreenState extends State<CatalogueScannerScreen> {
  final _text = TextEditingController();
  Exhibitor? _supplier;
  XFile? _image;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final picked = await CameraCaptureService.capture(() =>
        ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88));
    if (picked == null) return;
    setState(() {
      _busy = true;
      _image = picked;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(picked.path));
      _text.text = result.text;
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_supplier == null || _image == null || _text.text.trim().isEmpty) {
      return;
    }
    final root = await getApplicationDocumentsDirectory();
    final target = File(
        '${root.path}/catalogues/${await TeamWorkspaceService().scopeKey()}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await target.parent.create(recursive: true);
    await File(_image!.path).copy(target.path);
    await TradeDatabase.instance.addAttachment(Attachment(
        ownerType: 'exhibitor',
        ownerId: _supplier!.id!,
        kind: 'catalogue',
        path: target.path,
        note: 'Catalogue OCR\n${_text.text.trim()}',
        createdAt: DateTime.now()));
    await TradeDatabase.instance.logAudit('Scanned catalogue', _supplier!.name);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Catalogue scanner')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<Exhibitor>(
              initialValue: _supplier,
              items: widget.suppliers
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _supplier = v),
              decoration: const InputDecoration(labelText: 'Supplier')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(_busy
                  ? 'Reading catalogue...'
                  : 'Photograph catalogue page')),
          const SizedBox(height: 12),
          TextField(
              controller: _text,
              minLines: 12,
              maxLines: 20,
              decoration: const InputDecoration(
                  labelText: 'Extracted catalogue / price-list text')),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save to supplier files')),
        ]),
      );
}

class SupplierCommentsScreen extends StatefulWidget {
  final Exhibitor supplier;
  const SupplierCommentsScreen({super.key, required this.supplier});
  @override
  State<SupplierCommentsScreen> createState() => _SupplierCommentsScreenState();
}

class _SupplierCommentsScreenState extends State<SupplierCommentsScreen> {
  final _db = TradeDatabase.instance;
  final _comment = TextEditingController();
  late Future<List<Map<String, dynamic>>> _comments = _load();
  Future<List<Map<String, dynamic>>> _load() =>
      _db.queryAll('supplier_comments',
          where: 'exhibitor_id = ?',
          whereArgs: [widget.supplier.id],
          orderBy: 'created_at DESC');

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    final mentions = RegExp(r'@[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}')
        .allMatches(body)
        .map((m) => m.group(0)!.substring(1))
        .toList();
    await _db.insert('supplier_comments', {
      'exhibitor_id': widget.supplier.id,
      'body': body,
      'mentions_json': jsonEncode(mentions),
      'author_email': Supabase.instance.client.auth.currentUser?.email ?? '',
    });
    await _db.logAudit('Commented on supplier', widget.supplier.name);
    _comment.clear();
    setState(() => _comments = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Team notes - ${widget.supplier.name}')),
        body: Column(children: [
          Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _comments,
                  builder: (context, snapshot) {
                    final rows = snapshot.data;
                    if (rows == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (rows.isEmpty) {
                      return const EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'No team notes',
                          message:
                              'Add context or mention a teammate using @email.');
                    }
                    return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return Card(
                              child: ListTile(
                                  title: Text(row['body'] as String),
                                  subtitle: Text(
                                      '${row['author_email']} | ${row['created_at']}')));
                        });
                  })),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _comment,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                hintText: 'Add note or @mention email'))),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        tooltip: 'Send note',
                        onPressed: _add,
                        icon: const Icon(Icons.send)),
                  ]))),
        ]),
      );
}

class DueDiligenceScreen extends StatefulWidget {
  final Exhibitor supplier;
  const DueDiligenceScreen({super.key, required this.supplier});
  @override
  State<DueDiligenceScreen> createState() => _DueDiligenceScreenState();
}

class _DueDiligenceScreenState extends State<DueDiligenceScreen> {
  final _db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _checks = _load();
  static const types = [
    'Business registration',
    'Sanctions & watchlists',
    'Trademark / IP',
    'Website & domain',
    'Export references',
    'Factory address',
    'Bank-account match'
  ];
  Future<List<Map<String, dynamic>>> _load() =>
      _db.queryAll('due_diligence_checks',
          where: 'exhibitor_id = ?',
          whereArgs: [widget.supplier.id],
          orderBy: 'created_at DESC');

  Future<void> _runPreScreen() async {
    final existingTypes =
        (await _load()).map((row) => row['check_type']).toSet();
    Map<String, dynamic> verification = {};
    Map<String, dynamic> field = {};
    try {
      verification = Map<String, dynamic>.from(
          jsonDecode(widget.supplier.verificationJson) as Map);
    } catch (_) {}
    try {
      field = Map<String, dynamic>.from(
          jsonDecode(widget.supplier.fieldCaptureJson) as Map);
    } catch (_) {}
    final certificates = verification['certificates'] is List
        ? verification['certificates'] as List
        : const [];
    final checks = <(String, bool, String)>[
      (
        'Business registration',
        '${field['registration_number'] ?? ''}'.trim().isNotEmpty,
        'Captured registration number'
      ),
      (
        'Sanctions & watchlists',
        false,
        'External watchlist confirmation is still required'
      ),
      (
        'Trademark / IP',
        '${field['brand_ownership'] ?? ''}'.trim().isNotEmpty,
        'Brand ownership evidence'
      ),
      (
        'Website & domain',
        RegExp(r'https?://|www\.', caseSensitive: false)
            .hasMatch(widget.supplier.contactCompanyNotes),
        'Website reference in supplier notes'
      ),
      (
        'Export references',
        '${field['export_markets'] ?? ''}'.trim().isNotEmpty,
        'Export markets captured'
      ),
      (
        'Factory address',
        '${field['factory_address'] ?? ''}'.trim().isNotEmpty,
        'Factory address captured'
      ),
      (
        'Bank-account match',
        false,
        'Verify beneficiary name against legal company name before payment'
      ),
      (
        'Certificates',
        certificates.isNotEmpty,
        '${certificates.length} certificate records captured'
      ),
    ];
    for (final check in checks) {
      if (existingTypes.contains(check.$1)) continue;
      await _db.insert('due_diligence_checks', {
        'exhibitor_id': widget.supplier.id,
        'check_type': check.$1,
        'source': 'Automatic record pre-screen',
        'result': check.$3,
        'status': check.$2 ? 'Clear' : 'Needs review',
        'reviewed_at': DateTime.now().toIso8601String(),
      });
    }
    await _db.logAudit('Ran due-diligence pre-screen', widget.supplier.name);
    setState(() => _checks = _load());
  }

  Future<void> _add() async {
    var type = types.first;
    var status = 'Needs review';
    final source = TextEditingController();
    final result = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  title: const Text('Record due-diligence check'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                        initialValue: type,
                        items: types
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => type = v!),
                    const SizedBox(height: 10),
                    TextField(
                        controller: source,
                        decoration:
                            const InputDecoration(labelText: 'Source or URL')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: result,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: 'Finding / evidence')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                        initialValue: status,
                        items: ['Needs review', 'Clear', 'Concern', 'Blocked']
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => status = v!)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'))
                  ],
                )));
    if (save != true) return;
    await _db.insert('due_diligence_checks', {
      'exhibitor_id': widget.supplier.id,
      'check_type': type,
      'source': source.text.trim(),
      'result': result.text.trim(),
      'status': status,
      'reviewed_at': DateTime.now().toIso8601String()
    });
    setState(() => _checks = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Supplier due diligence'), actions: [
          IconButton(
              tooltip: 'Run record pre-screen',
              onPressed: _runPreScreen,
              icon: const Icon(Icons.auto_awesome_outlined)),
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add check')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _checks,
            builder: (context, snapshot) {
              final rows = snapshot.data;
              if (rows == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (rows.isEmpty) {
                return const EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No checks recorded',
                    message:
                        'Record the source and result of each external check.');
              }
              return ListView(
                  padding: const EdgeInsets.all(16),
                  children: rows
                      .map((row) => Card(
                              child: ListTile(
                            leading: Icon(row['status'] == 'Clear'
                                ? Icons.verified_outlined
                                : Icons.warning_amber_outlined),
                            title: Text(row['check_type']),
                            subtitle:
                                Text('${row['status']}\n${row['result']}'),
                            isThreeLine: true,
                          )))
                      .toList());
            }),
      );
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _db = TradeDatabase.instance;
  late Future<List<List<Map<String, dynamic>>>> _data = _load();
  Future<List<List<Map<String, dynamic>>>> _load() async => [
        await _db.queryAll('recycle_bin', orderBy: 'deleted_at DESC'),
        await _db.queryAll('record_versions', orderBy: 'created_at DESC'),
      ];
  void _refresh() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Recovery'),
            bottom: const TabBar(
                tabs: [Tab(text: 'Recycle bin'), Tab(text: 'Versions')])),
        body: FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: _data,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return TabBarView(children: [
                _list(snapshot.data![0], 'deleted_at',
                    (id) => _db.restoreRecycleItem(id)),
                _list(snapshot.data![1], 'created_at',
                    (id) => _db.restoreVersion(id)),
              ]);
            }),
      ));

  Widget _list(List<Map<String, dynamic>> rows, String dateKey,
      Future<void> Function(int) restore) {
    if (rows.isEmpty) {
      return const EmptyState(
          icon: Icons.restore_outlined,
          title: 'Nothing to recover',
          message:
              'Deleted items and earlier saved versions will appear here.');
    }
    return ListView(
        padding: const EdgeInsets.all(16),
        children: rows
            .take(100)
            .map((row) => Card(
                    child: ListTile(
                  title: Text(_restoreRecordLabel(row['record_type']?.toString() ?? '')),
                  subtitle: Text(row[dateKey]),
                  trailing: IconButton(
                      tooltip: 'Restore',
                      icon: const Icon(Icons.restore),
                      onPressed: () async {
                        await restore(row['id'] as int);
                        _refresh();
                      }),
                )))
            .toList());
  }

  String _restoreRecordLabel(String recordType) {
    const labels = {
      'supplier': 'Supplier',
      'product': 'Product',
      'contact': 'Contact',
      'meeting': 'Meeting',
      'quote': 'Quotation',
      'task': 'Task',
    };
    return labels[recordType] ?? 'Saved record';
  }
}

class PhotoMatchScreen extends StatefulWidget {
  final List<Exhibitor> suppliers;
  const PhotoMatchScreen({super.key, required this.suppliers});
  @override
  State<PhotoMatchScreen> createState() => _PhotoMatchScreenState();
}

class _PhotoMatchScreenState extends State<PhotoMatchScreen> {
  bool _busy = false;
  List<SimilarPhoto> _matches = const [];

  Future<void> _find() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _busy = true;
      _matches = const [];
    });
    final service = PhotoSimilarityService();
    final targetHash = await service.hashFile(picked.path);
    if (targetHash == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final rows = await TradeDatabase.instance.queryAll('attachments',
        where: "kind = 'image' OR kind = 'photo'", orderBy: 'created_at DESC');
    final matches = <SimilarPhoto>[];
    for (final row in rows.take(250)) {
      final hash = await service.hashFile(row['path'] as String);
      if (hash == null) continue;
      final similarity = service.compare(targetHash, hash);
      if (similarity < .55) continue;
      String supplier = 'Linked record';
      if (row['owner_type'] == 'exhibitor') {
        supplier = widget.suppliers
                .where((e) => e.id == row['owner_id'])
                .firstOrNull
                ?.name ??
            supplier;
      }
      matches.add(SimilarPhoto(
          attachmentId: row['id'] as int,
          path: row['path'] as String,
          supplierName: supplier,
          similarity: similarity));
    }
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    if (mounted) {
      setState(() {
        _busy = false;
        _matches = matches.take(20).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Product photo match')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _find,
            icon: const Icon(Icons.image_search),
            label: const Text('Choose photo')),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _matches.isEmpty
                ? const EmptyState(
                    icon: Icons.image_search_outlined,
                    title: 'Find similar products',
                    message:
                        'Choose a product photo to compare with saved field photos on this device.')
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _matches
                        .map((match) => Card(
                                child: ListTile(
                              leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(File(match.path),
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover)),
                              title: Text(match.supplierName),
                              subtitle: Text(
                                  '${(match.similarity * 100).round()}% visual similarity'),
                            )))
                        .toList()),
      );
}

class _FieldData {
  final List<Trip> trips;
  final List<Exhibitor> suppliers;
  final List<Meeting> meetings;
  final List<Sample> samples;
  const _FieldData(this.trips, this.suppliers, this.meetings, this.samples);
}

class _FieldSectionHeader extends StatelessWidget {
  final String label;
  const _FieldSectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text(label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            )),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
