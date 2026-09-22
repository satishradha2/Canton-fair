import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/reminder_service.dart';
import '../widgets/voice_note_field.dart';
import 'hall_route_screen.dart';
import 'ocr_screen.dart';
import 'sync_status_screen.dart';

class FieldCommandCenterScreen extends StatefulWidget {
  const FieldCommandCenterScreen({super.key});

  @override
  State<FieldCommandCenterScreen> createState() => _FieldCommandCenterScreenState();
}

class _FieldCommandCenterScreenState extends State<FieldCommandCenterScreen> {
  final _db = TradeDatabase.instance;
  late Future<_CommandData> _data = _load();
  bool _busy = false;
  String? _message;

  Future<_CommandData> _load() async => _CommandData(
        suppliers: await _db.queryAll('exhibitors'),
        meetings: await _db.queryAll('meetings', orderBy: 'meeting_date DESC'),
        products: await _db.queryAll('products'),
        expenses: await _db.queryAll('expenses', orderBy: 'incurred_at DESC'),
        conflicts: await _db.getCloudSyncConflicts(),
        trips: await _db.queryAll('trips', orderBy: 'created_at DESC'),
      );

  void _refresh() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await action();
      _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _planAppointment(_CommandData data) async {
    if (data.suppliers.isEmpty) {
      setState(() => _message = 'Import or capture a supplier before scheduling an appointment.');
      return;
    }
    var supplierId = data.suppliers.first['id'] as int;
    var at = DateTime.now().add(const Duration(hours: 1));
    final outcome = TextEditingController(text: 'Supplier appointment');
    final notes = TextEditingController();
    final created = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Plan supplier appointment'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: supplierId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: data.suppliers.map((supplier) => DropdownMenuItem(
              value: supplier['id'] as int, child: Text(supplier['name'] as String))).toList(),
            onChanged: (value) => setDialog(() => supplierId = value!),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Appointment time'), subtitle: Text(_dateTime(at)),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final date = await showDatePicker(context: context, initialDate: at,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)));
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(at));
              if (time != null) setDialog(() => at = DateTime(date.year, date.month, date.day, time.hour, time.minute));
            },
          ),
          TextField(controller: outcome, decoration: const InputDecoration(labelText: 'Purpose / planned outcome')),
          const SizedBox(height: 10),
          TextField(controller: notes, minLines: 3, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Agenda and visit notes')),
          const VoiceNoteAction(contextLabel: 'Supplier appointment agenda'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Schedule'))],
      ),
    ));
    if (created != true) return;
    final supplier = data.suppliers.firstWhere((item) => item['id'] == supplierId);
    await _run(() async {
      final id = await _db.insert('meetings', {
        'exhibitor_id': supplierId, 'meeting_date': at.toIso8601String(),
        'follow_up_date': at.toIso8601String(), 'outcome': outcome.text.trim().isEmpty ? 'Supplier appointment' : outcome.text.trim(),
        'priority': 'Medium', 'notes': notes.text.trim(), 'completed': 0,
      });
      await ReminderService.scheduleFollowUp(id: id, title: 'Appointment: ${supplier['name']}',
        body: outcome.text.trim().isEmpty ? 'Supplier appointment' : outcome.text.trim(), at: at);
      await _db.logAudit('Scheduled supplier appointment', '${supplier['name']} at ${_dateTime(at)}');
    });
  }

  Future<void> _addExpense(_CommandData data) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var category = 'Travel';
    var currency = 'CNY';
    final saved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Record daily expense'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'),
            items: const ['Travel', 'Meals', 'Samples', 'Courier', 'Accommodation', 'Other'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setDialog(() => category = value!)),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount')),
          DropdownButtonFormField<String>(initialValue: currency, decoration: const InputDecoration(labelText: 'Currency'),
            items: const ['CNY', 'USD', 'AED', 'EUR'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setDialog(() => currency = value!)),
          TextField(controller: note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Note / receipt reference')),
          const VoiceNoteAction(contextLabel: 'Field expense note'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save expense'))],
      ),
    ));
    if (saved != true) return;
    final parsedAmount = double.tryParse(amount.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      setState(() => _message = 'Enter an expense amount greater than zero.');
      return;
    }
    await _run(() async {
      await _db.insert('expenses', {'trip_id': null, 'exhibitor_id': null, 'category': category, 'amount': parsedAmount,
        'currency': currency, 'note': note.text.trim(), 'incurred_at': DateTime.now().toIso8601String()});
      await _db.logAudit('Recorded field expense', '$currency $parsedAmount - $category');
    });
  }

  Future<void> _importDirectory(_CommandData data) async {
    if (data.trips.isEmpty) {
      setState(() => _message = 'Create a trip before importing official fair exhibitors.');
      return;
    }
    final link = TextEditingController();
    var tripId = data.trips.first['id'] as int;
    final proceed = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Import official exhibitor directory'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Use an official fair CSV or JSON export/API link. A normal interactive webpage cannot be imported reliably without its permitted export or API.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(initialValue: tripId, isExpanded: true, decoration: const InputDecoration(labelText: 'Trip'),
            items: data.trips.map((trip) => DropdownMenuItem(value: trip['id'] as int, child: Text(trip['name'] as String))).toList(),
            onChanged: (value) => setDialog(() => tripId = value!)),
          TextField(controller: link, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Official CSV or JSON URL', hintText: 'https://fair.example/exhibitors.csv')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download and import'))],
      ),
    ));
    if (proceed != true || link.text.trim().isEmpty) return;
    await _run(() async {
      final uri = Uri.tryParse(link.text.trim());
      if (uri == null || !uri.hasScheme) throw StateError('Enter a valid official directory URL.');
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Directory download failed (${response.statusCode}).');
      final entries = _directoryEntries(response.body, response.headers['content-type'] ?? '', uri.path);
      var imported = 0;
      for (final entry in entries) {
        final name = _field(entry, ['name', 'company', 'company_name', 'exhibitor']);
        if (name.isEmpty) continue;
        await _db.insert('exhibitors', {'trip_id': tripId, 'name': name, 'hall': _field(entry, ['hall', 'hall_number']),
          'booth': _field(entry, ['booth', 'booth_number', 'stand']), 'category': _field(entry, ['category', 'product_category']),
          'country': _field(entry, ['country', 'region']), 'website': _field(entry, ['website', 'url'])});
        imported++;
      }
      if (imported == 0) throw StateError('No exhibitors were found. Use a CSV/JSON source with a name/company column.');
      await _db.logAudit('Imported official exhibitor directory', '$imported exhibitors from ${uri.host}');
      if (mounted) setState(() => _message = '$imported exhibitors imported. Open Hall route to plan the walk.');
    });
  }

  List<Map<String, dynamic>> _directoryEntries(String body, String contentType, String sourcePath) {
    final jsonSource = contentType.contains('json') || sourcePath.toLowerCase().endsWith('.json');
    if (jsonSource) {
      final decoded = jsonDecode(body);
      final list = decoded is List ? decoded : decoded is Map ? (decoded['data'] ?? decoded['exhibitors'] ?? decoded['results']) : null;
      if (list is! List) throw StateError('The JSON source must contain a data, exhibitors, or results list.');
      return list.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
    final rows = const CsvToListConverter().convert(body);
    if (rows.length < 2) return const [];
    final headers = rows.first.map((item) => item.toString().trim().toLowerCase()).toList();
    return rows.skip(1).map((row) => <String, dynamic>{
      for (var index = 0; index < headers.length && index < row.length; index++) headers[index]: row[index],
    }).toList();
  }

  String _field(Map<String, dynamic> source, List<String> names) {
    for (final name in names) { final value = source[name]; if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim(); }
    return '';
  }

  String _dateTime(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${TimeOfDay.fromDateTime(date).format(context)}';

  @override
  Widget build(BuildContext context) => DefaultTabController(length: 4, child: Scaffold(
    appBar: AppBar(title: const Text('Field command center'), bottom: const TabBar(tabs: [
      Tab(icon: Icon(Icons.today_outlined), text: 'Today'), Tab(icon: Icon(Icons.event_outlined), text: 'Appointments'),
      Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Expenses'), Tab(icon: Icon(Icons.map_outlined), text: 'Directory'),
    ])),
    body: FutureBuilder<_CommandData>(future: _data, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Could not load field tools: ${snapshot.error}'));
      final data = snapshot.data!;
      return AbsorbPointer(absorbing: _busy, child: TabBarView(children: [
        _today(data), _appointments(data), _expenses(data), _directory(data),
      ]));
    }),
  ));

  Widget _today(_CommandData data) {
    final today = DateUtils.dateOnly(DateTime.now());
    final visited = data.meetings.where((item) => DateUtils.isSameDay(DateTime.tryParse('${item['meeting_date']}'), today)).length;
    final open = data.meetings.where((item) => item['completed'] != 1 && item['follow_up_date'] != null).length;
    final quotes = data.products.where((item) => item['quoted_price'] != null).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('End-of-day field report', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6), const Text('A live operational summary from records captured on this device.'),
      const SizedBox(height: 18), Wrap(spacing: 10, runSpacing: 10, children: [
        _metric('Supplier visits', '$visited', Icons.storefront_outlined), _metric('Products captured', '${data.products.length}', Icons.inventory_2_outlined),
        _metric('Open follow-ups', '$open', Icons.task_alt_outlined), _metric('Quoted products', '$quotes', Icons.payments_outlined),
        _metric('Sync conflicts', '${data.conflicts.length}', Icons.compare_arrows_outlined), _metric('Expenses today', '${data.expenses.where((item) => DateUtils.isSameDay(DateTime.tryParse('${item['incurred_at']}'), today)).length}', Icons.receipt_long_outlined),
      ]),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      ListTile(leading: const Icon(Icons.document_scanner_outlined), title: const Text('Business-card OCR review queue'),
        subtitle: const Text('Open the card review flow to compare the card images and extracted fields before saving.'),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OcrScreen()))),
      ListTile(leading: const Icon(Icons.compare_arrows_outlined), title: const Text('Resolve offline conflicts'),
        subtitle: Text(data.conflicts.isEmpty ? 'No unresolved conflicts' : '${data.conflicts.length} records need a local or cloud decision'),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncStatusScreen()))),
    ]);
  }

  Widget _appointments(_CommandData data) => ListView(padding: const EdgeInsets.all(20), children: [
    FilledButton.icon(onPressed: () => _planAppointment(data), icon: const Icon(Icons.add), label: const Text('Schedule appointment')),
    const SizedBox(height: 16),
    ...data.meetings.where((item) => item['follow_up_date'] != null).take(30).map((item) => Card(child: ListTile(
      leading: Icon(item['completed'] == 1 ? Icons.task_alt : Icons.event_outlined), title: Text('${item['outcome'] ?? 'Appointment'}'),
      subtitle: Text('${item['follow_up_date'] ?? item['meeting_date']}\n${item['notes'] ?? ''}'), isThreeLine: true,
    ))),
  ]);

  Widget _expenses(_CommandData data) => ListView(padding: const EdgeInsets.all(20), children: [
    FilledButton.icon(onPressed: () => _addExpense(data), icon: const Icon(Icons.add), label: const Text('Record expense')),
    const SizedBox(height: 12), const Text('For a receipt photo, use the existing Expense workflow in Field operations; its attachment is retained with the expense record.'),
    const SizedBox(height: 12), ...data.expenses.take(30).map((item) => Card(child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined), title: Text('${item['currency']} ${item['amount']}'),
      subtitle: Text('${item['category']} · ${item['incurred_at']}\n${item['note'] ?? ''}'), isThreeLine: true,
    ))),
  ]);

  Widget _directory(_CommandData data) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Exhibitor directory and booth navigation', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8), const Text('Import a sanctioned fair CSV/JSON source, then use the hall map and sorted booth route offline.'),
    const SizedBox(height: 16), FilledButton.icon(onPressed: () => _importDirectory(data), icon: const Icon(Icons.download_outlined), label: const Text('Import official directory URL')),
    const SizedBox(height: 10), OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HallRouteScreen())), icon: const Icon(Icons.map_outlined), label: const Text('Open hall map and next-best route')),
    const SizedBox(height: 20), Text('${data.suppliers.length} suppliers available for route planning.'),
  ]);

  Widget _metric(String label, String value, IconData icon) => SizedBox(width: 156, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), const SizedBox(height: 12), Text(value, style: Theme.of(context).textTheme.headlineSmall), Text(label)]))));
}

class _CommandData {
  final List<Map<String, dynamic>> suppliers, meetings, products, expenses, conflicts, trips;
  const _CommandData({required this.suppliers, required this.meetings, required this.products, required this.expenses, required this.conflicts, required this.trips});
}
