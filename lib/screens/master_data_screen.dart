import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/approval_policy.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'product_category_master_screen.dart';

class MasterDataScreen extends StatefulWidget {
  const MasterDataScreen({super.key});

  @override
  State<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends State<MasterDataScreen> {
  static const _hallMarker = '\n\n[fair-expert-halls]';
  late Future<List<Trip>> _fairs;
  bool _busy = false;

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
        setState(() => _fairs = _load());
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
        setState(() => _fairs = _load());
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
            DropdownButtonFormField<Trip>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Fair'),
              items: fairs.map((fair) => DropdownMenuItem(value: fair, child: Text(fair.name, overflow: TextOverflow.ellipsis))).toList(),
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
        body: FutureBuilder<List<Trip>>(
          future: _fairs,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final fairs = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Shared master data', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Members and administrators can create the shared lists used by Fair Expert.'),
                const SizedBox(height: 24),
                _masterTile(Icons.category_outlined, 'Product categories', 'Create the product category list used by your team.', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductCategoryMasterScreen()))),
                const SizedBox(height: 12),
                _masterTile(Icons.event_outlined, 'Fair names', 'Create and maintain fairs for supplier capture.', _busy ? null : _createFair),
                const SizedBox(height: 12),
                _masterTile(Icons.maps_home_work_outlined, 'Halls', 'Add reusable hall names under a selected fair.', _busy ? null : () => _createHall(fairs)),
                const SizedBox(height: 28),
                Text('Fairs and halls', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (fairs.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No fairs created yet. Start by creating the fair name.'))),
                ...fairs.map((fair) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fair.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if (fair.city.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(fair.city)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _halls(fair).isEmpty ? [const Chip(label: Text('No halls yet'))] : _halls(fair).map((hall) => Chip(label: Text(hall))).toList()),
                ])))),
              ],
            );
          },
        ),
      );

  Widget _masterTile(IconData icon, String title, String subtitle, VoidCallback? onTap) => Card(
        child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}
