import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/approval_policy.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'product_category_master_screen.dart';
import '../widgets/record_search.dart';
import '../widgets/database_paged_list.dart';
import '../data/record_page_service.dart';
import '../widgets/focused_workspace.dart';

class MasterDataScreen extends StatefulWidget {
  const MasterDataScreen({super.key});

  @override
  State<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends State<MasterDataScreen> {
  static const _hallMarker = '\n\n[fair-expert-halls]';
  late Future<List<Trip>> _fairs;
  bool _busy = false;
  int _panel = 0;
  int? _hallFair;
  final _categoryKey = GlobalKey<ProductCategoryMasterScreenState>();
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _fairs = _load();
  }

  Future<List<Trip>> _load() async => (await TradeDatabase.instance.getTrips())
      .where((trip) => trip.name != 'Fair Expert contacts')
      .toList();

  Future<bool> _canWrite() async {
    try {
      await ApprovalPolicy.requireWriter();
      return true;
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Bad state: ', ''));
      return false;
    }
  }

  Future<void> _createFair() async {
    if (!await _canWrite() || !mounted) return;
    final values = await _fairDialog();
    if (values == null || values.$1.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await TradeDatabase.instance.insertTrip(Trip(name: values.$1.trim(), city: values.$2.trim()));
      if (mounted) {
        setState(() { _fairs = _load(); _revision++; });
        _message('Fair created. You can now add its halls.');
      }
    } catch (error) {
      if (mounted) _message('Could not create fair: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createHall(List<Trip> fairs) async {
    if (!await _canWrite() || !mounted) return;
    if (fairs.isEmpty) {
      _message('Create a fair before adding halls.');
      return;
    }
    final values = await _hallDialog(fairs);
    if (values == null || values.$2.trim().isEmpty) return;
    final fair = values.$1;
    final halls = _halls(fair);
    final clean = values.$2.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (halls.any((hall) => hall.toLowerCase() == clean.toLowerCase())) {
      _message('That hall already exists for ${fair.name}.');
      return;
    }
    setState(() => _busy = true);
    try {
      halls.add(clean);
      await TradeDatabase.instance.update('trips', fair.id!, {
        ...fair.toMap()..remove('id'),
        'notes': _withHalls(fair.notes, halls),
      });
      if (mounted) {
        setState(() { _fairs = _load(); _revision++; });
        _message('$clean added to ${fair.name}.');
      }
    } catch (error) {
      if (mounted) _message('Could not create hall: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _halls(Trip fair) {
    final markerIndex = fair.notes.indexOf(_hallMarker);
    if (markerIndex == -1) return [];
    try {
      final value = jsonDecode(fair.notes.substring(markerIndex + _hallMarker.length));
      return (value as List).whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  String _withHalls(String notes, List<String> halls) {
    final markerIndex = notes.indexOf(_hallMarker);
    final plainNotes = markerIndex == -1 ? notes : notes.substring(0, markerIndex);
    return '$plainNotes$_hallMarker${jsonEncode(halls)}';
  }

  Future<(String, String)?> _fairDialog() async {
    final name = TextEditingController();
    final city = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create fair'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Fair name', hintText: 'Example: Canton Fair 2026')),
          const SizedBox(height: 12),
          TextField(controller: city, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'City (optional)', hintText: 'Example: Guangzhou')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, (name.text, city.text)), child: const Text('Create fair')),
        ],
      ),
    );
    name.dispose();
    city.dispose();
    return result;
  }

  Future<(Trip, String)?> _hallDialog(List<Trip> fairs) async {
    Trip selected = fairs.first;
    final hall = TextEditingController();
    final result = await showDialog<(Trip, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Create hall'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SearchableSelectionField<Trip>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Fair'),
              options: fairs, labelFor: (fair) => fair.name,
              onChanged: (fair) { if (fair != null) setModalState(() => selected = fair); },
            ),
            const SizedBox(height: 12),
            TextField(controller: hall, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Hall name or number', hintText: 'Example: Hall 1.2')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, (selected, hall.text)), child: const Text('Create hall')),
          ],
        ),
      ),
    );
    hall.dispose();
    return result;
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Masters')),
    body: FutureBuilder<List<Trip>>(future: _fairs, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('Could not load masters: ${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final fairs = snapshot.data!;
      return FocusedWorkspace(title: 'Shared master data',
        subtitle: 'Members and administrators can create the lists used across Fair Expert.',
        busy: _busy, index: _panel, onChanged: (index) => setState(() => _panel = index),
        labels: const ['Categories', 'Fairs', 'Halls'],
        icons: const [Icons.category_outlined, Icons.event_outlined, Icons.maps_home_work_outlined],
        sections: [
          ProductCategoryMasterScreen(key: _categoryKey, embedded: true),
          Padding(padding: const EdgeInsets.all(16), child: DatabasePagedList(refreshToken: _revision,
            loader: RecordPageService.fairs, searchHint: 'Search fair or city', emptyMessage: 'No fairs yet. Use Create new fair.',
            itemBuilder: (context, row) {
              final fair = Trip.fromMap(Map<String, dynamic>.from(row));
              return Card(child: ListTile(leading: const Icon(Icons.event_outlined),
                title: Text(fair.name), subtitle: Text('${fair.city}\n${_halls(fair).length} halls'), isThreeLine: true,
                trailing: IconButton(tooltip: 'Add hall to this fair', onPressed: _busy ? null : () => _createHall([fair]), icon: const Icon(Icons.add_location_alt_outlined))));
            })),
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            SearchableSelectionField<int>(key: ValueKey(_hallFair), value: _hallFair,
              decoration: const InputDecoration(labelText: 'Filter by fair (optional)'),
              options: fairs.map((fair) => fair.id!).toList(), labelFor: (id) => fairs.firstWhere((fair) => fair.id == id).name,
              onChanged: (value) => setState(() => _hallFair = value)),
            if (_hallFair != null) Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => _hallFair = null), child: const Text('All fairs'))),
            const SizedBox(height: 12),
            Expanded(child: DatabasePagedList(key: ValueKey(_hallFair), refreshToken: _revision,
              loader: (offset, limit, query) => RecordPageService.halls(offset, limit, query, fairId: _hallFair),
              searchHint: 'Search hall or fair', emptyMessage: 'No halls yet. Create a fair, then add its halls.',
              itemBuilder: (_, row) => Card(child: ListTile(leading: const Icon(Icons.maps_home_work_outlined),
                title: Text(row['name'].toString()), subtitle: Text(row['fair_name'].toString()))))),
          ])),
        ],
        footer: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy ? null : () {
            if (_panel == 0) { _categoryKey.currentState?.createCategory(); }
            else if (_panel == 1) { _createFair(); }
            else { _createHall(_hallFair == null ? fairs : fairs.where((fair) => fair.id == _hallFair).toList()); }
          }, icon: const Icon(Icons.add), label: Text('Create new ${['category','fair','hall'][_panel]}'))),
      );
    }));
}