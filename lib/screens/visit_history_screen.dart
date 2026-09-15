import 'package:flutter/material.dart';
import '../data/visit_ai_service.dart';
import 'visit_recording_screen.dart';

class VisitHistoryScreen extends StatefulWidget {
  const VisitHistoryScreen({super.key, required this.scope, required this.tripId});
  final String scope;
  final int tripId;

  @override
  State<VisitHistoryScreen> createState() => _VisitHistoryScreenState();
}

class _VisitHistoryScreenState extends State<VisitHistoryScreen> {
  final _service = VisitAiService();
  late Future<List<Map<String, Object?>>> _data;
  String _query = '';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _data = _service.visits(widget.scope, widget.tripId);
  }

  void _refresh() => setState(() {
    _data = _service.visits(widget.scope, widget.tripId);
  });

  String _date(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Date unavailable';
    return '${date.day}/${date.month}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Visit history'), actions: [
      IconButton(onPressed: _refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        TextField(decoration: const InputDecoration(labelText: 'Find a visit',
          hintText: 'Supplier, hall, booth, or team member', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase())),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: _status,
          decoration: const InputDecoration(labelText: 'Visit status'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All visits')),
            DropdownMenuItem(value: 'completed', child: Text('Completed')),
            DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
            DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
          ], onChanged: (value) => setState(() => _status = value!)),
      ])),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(padding: const EdgeInsets.all(24), children: [
              Text('Could not load visits: ${snapshot.error}'),
              TextButton(onPressed: _refresh, child: const Text('Try again')),
            ]);
          }
          final rows = (snapshot.data ?? []).where((row) =>
            (_status == 'all' || row['status'] == _status) &&
            ['supplier_name', 'hall', 'booth', 'owner_email'].map((key) => row[key] ?? '')
              .join(' ').toLowerCase().contains(_query)).toList();
          if (rows.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24), child: Text('No visits match these filters.')));
          }
          return ListView.builder(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: rows.length, itemBuilder: (context, index) {
              final row = rows[index];
              return Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(row['supplier_name'] as String),
                subtitle: Text('${_date(row['started_at'])} | ${row['status'].toString().replaceAll('_', ' ')}\n'
                  'Hall ${row['hall'] ?? '-'} / Booth ${row['booth'] ?? '-'}\n'
                  '${row['owner_email'] ?? ''}\nView recordings, transcripts and reports'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => VisitRecordingScreen(scope: widget.scope,
                    visitId: row['id'] as int, supplierName: row['supplier_name'] as String,
                    reviewOnly: true))),
              ));
            });
        })),
    ]),
  );
}
