import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import 'scanner_screen.dart';
import 'ocr_screen.dart';

class CapturesScreen extends StatefulWidget {
  const CapturesScreen({super.key});

  @override
  State<CapturesScreen> createState() => _CapturesScreenState();
}

class _VisitQueues {
  final List<Exhibitor> needToVisit;
  final List<Exhibitor> visitedToday;

  const _VisitQueues({required this.needToVisit, required this.visitedToday});
}

class _CapturesScreenState extends State<CapturesScreen> {
  final db = TradeDatabase.instance;
  int? _tripFilter;
  String _query = '';
  bool _shortlistOnly = false;
  late Future<List<Trip>> _trips;
  late Future<List<Exhibitor>> _exhibitors;
  late Future<_VisitQueues> _visitQueues;
  late Future<List<Exhibitor>> _itinerary;
  late DateTime _itineraryDate;

  @override
  void initState() {
    super.initState();
    _trips = db.getTrips();
    _itineraryDate = DateTime.now();
    _load();
  }

  void _load() {
    setState(() {
      _visitQueues = _loadVisitQueues();
      _itinerary = _loadItinerary();
      if (_query.isNotEmpty) {
        _exhibitors = db.searchExhibitors(_query);
      } else if (_shortlistOnly) {
        _exhibitors = db.queryAll('exhibitors', orderBy: 'name ASC').then(
              (rows) => rows
                  .map((e) => Exhibitor.fromMap(e))
                  .where((it) => it.shortlisted)
                  .toList(),
            );
      } else {
        _exhibitors = db.getExhibitors(_tripFilter);
      }
    });
  }

  Future<List<Exhibitor>> _loadItinerary() async {
    final suppliers = await db.getExhibitors(_tripFilter);
    final day =
        DateTime(_itineraryDate.year, _itineraryDate.month, _itineraryDate.day);
    final itinerary = suppliers.where((supplier) {
      final planned = supplier.plannedVisitAt?.toLocal();
      return planned != null &&
          planned.year == day.year &&
          planned.month == day.month &&
          planned.day == day.day;
    }).toList()
      ..sort((a, b) => a.plannedVisitAt!.compareTo(b.plannedVisitAt!));
    return itinerary;
  }

  Future<_VisitQueues> _loadVisitQueues() async {
    final suppliers = await db.getExhibitors(_tripFilter);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final needToVisit =
        suppliers.where((supplier) => supplier.visitedAt == null).toList()
          ..sort((a, b) {
            final aDate = a.plannedVisitAt ?? DateTime(9999);
            final bDate = b.plannedVisitAt ?? DateTime(9999);
            return aDate.compareTo(bDate);
          });
    final visitedToday = suppliers.where((supplier) {
      final visited = supplier.visitedAt;
      return visited != null &&
          visited.year == today.year &&
          visited.month == today.month &&
          visited.day == today.day;
    }).toList()
      ..sort((a, b) => b.visitedAt!.compareTo(a.visitedAt!));
    return _VisitQueues(
      needToVisit: needToVisit,
      visitedToday: visitedToday,
    );
  }

  Future<List<Exhibitor>> _getDuplicateCandidates(Exhibitor candidate) async {
    final rows = await db.getExhibitors(null);
    return rows.where((e) {
      final sameName =
          e.name.toLowerCase().trim() == candidate.name.toLowerCase().trim();
      final sameBooth = e.booth.isNotEmpty &&
          e.booth.toLowerCase().trim() == candidate.booth.toLowerCase().trim();
      final boothMatch =
          e.booth.isNotEmpty && candidate.booth.isNotEmpty && sameBooth;
      return sameName || boothMatch;
    }).toList();
  }

  Future<bool> _showDuplicateCheck(Exhibitor candidate) async {
    final matches = await _getDuplicateCandidates(candidate);
    if (matches.isEmpty) return true;
    if (!mounted) return true;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Possible duplicates found'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('A supplier with similar details already exists.'),
            const SizedBox(height: 8),
            ...matches.map(
              (m) => ListTile(
                title: Text(m.name),
                subtitle: Text('Booth: ${m.booth} | Country: ${m.country}'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue anyway'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel capture'),
          ),
        ],
      ),
    );
    return allow ?? true;
  }

  Future<Map<String, String>> _parseScannerPayload(String input) async {
    final map = <String, String>{};
    final lines = input
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final line in lines) {
      if (line.contains(':')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts[0].toLowerCase();
          final value = parts.sublist(1).join(':').trim();
          if (key.contains('name') || key.contains('company')) {
            map['name'] = value;
          } else if (key.contains('booth')) {
            map['booth'] = value;
          } else if (key.contains('hall')) {
            map['hall'] = value;
          } else if (key.contains('category')) {
            map['category'] = value;
          } else if (key.contains('country')) {
            map['country'] = value;
          } else if (key.contains('phone') || key.contains('mobile')) {
            map['phone'] = value;
          } else if (key.contains('email')) {
            map['email'] = value;
          } else if (key.contains('wechat')) {
            map['wechat'] = value;
          } else if (key.contains('name') && key.contains('contact')) {
            map['person'] = value;
          }
        }
      }
    }
    if (map.isNotEmpty) return map;
    final simple = input
        .split(RegExp(r'[;,\r\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (simple.isNotEmpty) {
      map['name'] = simple[0];
      if (simple.length > 1) map['booth'] = simple[1];
      if (simple.length > 2) map['country'] = simple[2];
    }
    return map;
  }

  Future<void> _openScanner() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (value == null || value.trim().isEmpty) return;
    final parsed = await _parseScannerPayload(value);
    await _openAddExhibitorSheet(prefill: parsed);
    if (!mounted) return;
  }

  Future<void> _openOcrCapture() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const OcrScreen()));
    if (value == null || value.trim().isEmpty) return;
    final parsed = await _parseScannerPayload(value);
    await _openAddExhibitorSheet(prefill: parsed);
    if (!mounted) return;
  }

  Future<void> _openCloseTripSheet(int tripId) async {
    final trip = await db.getTripById(tripId);
    if (trip == null) return;
    final noteController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close trip: ${trip.name}'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Closeout note',
            hintText: 'Optional notes about outstanding actions',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Mark closed'),
            onPressed: () async {
              await db.closeTrip(tripId, note: noteController.text.trim());
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Trip "${trip.name}" has been marked closed')),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openAddTripSheet() async {
    final formKey = GlobalKey<FormState>();
    String name = 'Canton Fair Trip';
    String city = 'Guangzhou';
    String start = '';
    String end = '';
    String notes = '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Trip'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Trip name'),
                  onSaved: (v) => name = v?.trim() ?? name,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'City'),
                  onSaved: (v) => city = v?.trim() ?? city,
                ),
                TextFormField(
                  decoration:
                      const InputDecoration(labelText: 'Start date YYYY-MM-DD'),
                  onSaved: (v) => start = v?.trim() ?? '',
                ),
                TextFormField(
                  decoration:
                      const InputDecoration(labelText: 'End date YYYY-MM-DD'),
                  onSaved: (v) => end = v?.trim() ?? '',
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Notes'),
                  onSaved: (v) => notes = v?.trim() ?? '',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Save'),
            onPressed: () async {
              formKey.currentState?.save();
              final trip = Trip(
                name: name,
                city: city,
                notes: notes,
                startDate: _parseDate(start),
                endDate: _parseDate(end),
              );
              await db.insertTrip(trip);
              _trips = db.getTrips();
              if (!mounted) return;
              Navigator.pop(ctx);
              _load();
            },
          ),
        ],
      ),
    );
  }

  DateTime? _parseDate(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return DateTime.parse(text.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAddExhibitorSheet({Map<String, String>? prefill}) async {
    final formKey = GlobalKey<FormState>();
    final seed = prefill ?? {};
    String name = seed['name']?.isNotEmpty == true ? seed['name']! : 'Supplier';
    String booth = seed['booth']?.isNotEmpty == true ? seed['booth']! : '';
    String hall = seed['hall']?.isNotEmpty == true ? seed['hall']! : '';
    String category =
        seed['category']?.isNotEmpty == true ? seed['category']! : '';
    String country =
        seed['country']?.isNotEmpty == true ? seed['country']! : '';
    String notes = '';
    int rating = 0;
    bool shortlisted = false;
    final trips = await _trips;
    int selectedTrip = trips.isNotEmpty ? trips.first.id! : 0;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Exhibitor / Supplier'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (trips.isEmpty)
                  const Text('Create a trip first to attach exhibitor records.')
                else
                  DropdownButtonFormField<int>(
                    value: selectedTrip,
                    items: trips
                        .where((t) => t.id != null)
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => selectedTrip = v ?? selectedTrip,
                  ),
                TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Supplier Name'),
                    onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Booth'),
                    onSaved: (v) => booth = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Hall'),
                    onSaved: (v) => hall = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Category'),
                    onSaved: (v) => category = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Country'),
                    onSaved: (v) => country = v?.trim() ?? ''),
                TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Company notes'),
                    onSaved: (v) => notes = v?.trim() ?? ''),
                DropdownButtonFormField<int>(
                  value: rating,
                  items: List.generate(
                    6,
                    (i) => DropdownMenuItem(value: i, child: Text('Rating $i')),
                  ),
                  onChanged: (v) => rating = v ?? 0,
                  decoration:
                      const InputDecoration(labelText: 'Initial rating'),
                ),
                CheckboxListTile(
                  value: shortlisted,
                  title: const Text('Add to shortlist'),
                  onChanged: (v) => shortlisted = v ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Save'),
            onPressed: () async {
              formKey.currentState?.save();
              final candidate = Exhibitor(
                tripId: selectedTrip,
                name: name,
                booth: booth,
                hall: hall,
                category: category,
                country: country,
                contactCompanyNotes: notes,
                shortlisted: shortlisted,
                rating: rating,
              );
              final allow = await _showDuplicateCheck(candidate);
              if (!allow) {
                return;
              }
              await db.upsertExhibitor(candidate);
              _load();
              if (!mounted) return;
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openDeleteTripDialog(int tripId) async {
    final trip = await db.getTripById(tripId);
    if (trip == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trip'),
        content: Text(
            'Delete "${trip.name}" and all linked exhibitors, products, contacts, meetings, and attachments?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await db.deleteTripCascade(tripId);
    _tripFilter = null;
    _trips = db.getTrips();
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Trip "${trip.name}" deleted')));
  }

  Future<void> _openEditExhibitorSheet(Exhibitor e) async {
    final formKey = GlobalKey<FormState>();
    String name = e.name;
    String booth = e.booth;
    String hall = e.hall;
    String category = e.category;
    String country = e.country;
    String notes = e.contactCompanyNotes;
    int rating = e.rating;
    bool shortlisted = e.shortlisted;
    final trips = await _trips;
    int selectedTrip = e.tripId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Supplier'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  value: selectedTrip,
                  items: trips
                      .where((t) => t.id != null)
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => selectedTrip = v ?? selectedTrip,
                  decoration: const InputDecoration(labelText: 'Trip'),
                ),
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(labelText: 'Supplier Name'),
                  onSaved: (v) => name = v?.trim() ?? name,
                ),
                TextFormField(
                  initialValue: booth,
                  decoration: const InputDecoration(labelText: 'Booth'),
                  onSaved: (v) => booth = v?.trim() ?? '',
                ),
                TextFormField(
                  initialValue: hall,
                  decoration: const InputDecoration(labelText: 'Hall'),
                  onSaved: (v) => hall = v?.trim() ?? '',
                ),
                TextFormField(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  onSaved: (v) => category = v?.trim() ?? '',
                ),
                TextFormField(
                  initialValue: country,
                  decoration: const InputDecoration(labelText: 'Country'),
                  onSaved: (v) => country = v?.trim() ?? '',
                ),
                TextFormField(
                  initialValue: notes,
                  decoration: const InputDecoration(labelText: 'Company notes'),
                  onSaved: (v) => notes = v?.trim() ?? '',
                ),
                DropdownButtonFormField<int>(
                  value: rating,
                  items: List.generate(
                    6,
                    (i) => DropdownMenuItem(value: i, child: Text('Rating $i')),
                  ),
                  onChanged: (v) => rating = v ?? 0,
                ),
                CheckboxListTile(
                  value: shortlisted,
                  title: const Text('Shortlist this supplier'),
                  onChanged: (v) => shortlisted = v ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Save changes'),
            onPressed: () async {
              formKey.currentState?.save();
              await db.update(
                'exhibitors',
                e.id!,
                Exhibitor(
                  id: e.id,
                  tripId: selectedTrip,
                  name: name,
                  booth: booth,
                  hall: hall,
                  category: category,
                  country: country,
                  contactCompanyNotes: notes,
                  shortlisted: shortlisted,
                  rating: rating,
                  tagsJson: e.tagsJson,
                  qualityScore: e.qualityScore,
                  responseSpeedScore: e.responseSpeedScore,
                  trustScore: e.trustScore,
                  moqFitScore: e.moqFitScore,
                  reliabilityScore: e.reliabilityScore,
                ).toMap()
                  ..remove('id'),
              );
              _load();
              if (!mounted) return;
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openMergeDuplicateDialog(Exhibitor source) async {
    final candidates = await _getDuplicateCandidates(source);
    final deduped = candidates.where((it) => it.id != source.id).toList();
    if (deduped.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No duplicate found for ${source.name}')),
      );
      return;
    }

    final targetId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose master supplier'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: deduped
                .map(
                  (it) => ListTile(
                    title: Text(it.name),
                    subtitle:
                        Text('Booth: ${it.booth} | Country: ${it.country}'),
                    onTap: () => Navigator.pop(ctx, it.id),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (targetId == null || targetId == source.id || source.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge duplicate'),
        content: const Text(
            'Move all contacts, products, and history to selected supplier and delete duplicate.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Merge')),
        ],
      ),
    );
    if (confirm != true) return;

    await db.mergeExhibitorRecords(targetId, source.id!);
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duplicate merged successfully.')));
  }

  Future<void> _openDeleteExhibitorDialog(Exhibitor e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete supplier'),
        content: const Text(
            'Delete supplier and all linked products, contacts, meetings, and attachments?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await db.deleteExhibitorCascade(e.id!);
    _load();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Supplier "${e.name}" deleted')));
  }

  Future<void> _openEditContactSheet(Contact c) async {
    final formKey = GlobalKey<FormState>();
    String name = c.name;
    String designation = c.designation;
    String phone = c.phone;
    String email = c.email;
    String whatsapp = c.whatsapp;
    String wechat = c.wechat;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Contact'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                    initialValue: name,
                    decoration:
                        const InputDecoration(labelText: 'Contact Name'),
                    onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(
                    initialValue: designation,
                    decoration: const InputDecoration(labelText: 'Designation'),
                    onSaved: (v) => designation = v?.trim() ?? ''),
                TextFormField(
                    initialValue: phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    onSaved: (v) => phone = v?.trim() ?? ''),
                TextFormField(
                    initialValue: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    onSaved: (v) => email = v?.trim() ?? ''),
                TextFormField(
                    initialValue: whatsapp,
                    decoration: const InputDecoration(labelText: 'WhatsApp'),
                    onSaved: (v) => whatsapp = v?.trim() ?? ''),
                TextFormField(
                    initialValue: wechat,
                    decoration: const InputDecoration(labelText: 'WeChat'),
                    onSaved: (v) => wechat = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Save changes'),
            onPressed: () async {
              formKey.currentState?.save();
              await db.update(
                'contacts',
                c.id!,
                Contact(
                  id: c.id,
                  exhibitorId: c.exhibitorId,
                  name: name,
                  designation: designation,
                  phone: phone,
                  email: email,
                  whatsapp: whatsapp,
                  wechat: wechat,
                ).toMap()
                  ..remove('id'),
              );
              _load();
              if (!mounted) return;
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openEditProductSheet(Product p) async {
    final formKey = GlobalKey<FormState>();
    String name = p.name;
    String model = p.modelCode;
    String specs = p.specs;
    String currency = p.priceCurrency;
    double? moq = p.moq;
    double? price = p.quotedPrice;
    String lead = p.leadTime;
    String terms = p.paymentTerms;
    bool shortlisted = p.shortlisted;
    int rating = p.rating;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Edit Product'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextFormField(
                      initialValue: name,
                      decoration:
                          const InputDecoration(labelText: 'Product Name'),
                      onSaved: (v) => name = v?.trim() ?? name),
                  TextFormField(
                      initialValue: model,
                      decoration:
                          const InputDecoration(labelText: 'Model / SKU'),
                      onSaved: (v) => model = v?.trim() ?? ''),
                  TextFormField(
                      initialValue: specs,
                      decoration: const InputDecoration(labelText: 'Specs'),
                      onSaved: (v) => specs = v?.trim() ?? ''),
                  TextFormField(
                    initialValue: p.moq?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'MOQ'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setStateDialog(() => moq = double.tryParse(v)),
                    onSaved: (v) => moq = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                    initialValue: p.quotedPrice?.toString() ?? '',
                    decoration:
                        const InputDecoration(labelText: 'Quoted price'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setStateDialog(() => price = double.tryParse(v)),
                    onSaved: (v) => price = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                      initialValue: currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      onSaved: (v) => currency = v?.trim() ?? 'USD'),
                  TextFormField(
                    initialValue: lead,
                    decoration: const InputDecoration(labelText: 'Lead time'),
                    onChanged: (v) => setStateDialog(() => lead = v.trim()),
                    onSaved: (v) => lead = v?.trim() ?? '',
                  ),
                  TextFormField(
                      initialValue: terms,
                      decoration:
                          const InputDecoration(labelText: 'Payment terms'),
                      onSaved: (v) => terms = v?.trim() ?? ''),
                  DropdownButtonFormField<int>(
                    value: rating,
                    items: List.generate(
                        6,
                        (i) => DropdownMenuItem(
                            value: i, child: Text('Rating $i'))),
                    onChanged: (v) => setStateDialog(() => rating = v ?? 0),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Live shortlist score: ${_productShortlistScoreForValues(rating: rating, quotedPrice: price, moq: moq, leadTime: lead).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: shortlisted,
                    title: const Text('Shortlist this product'),
                    onChanged: (v) =>
                        setStateDialog(() => shortlisted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              child: const Text('Save changes'),
              onPressed: () async {
                formKey.currentState?.save();
                await db.update(
                  'products',
                  p.id!,
                  Product(
                    id: p.id,
                    exhibitorId: p.exhibitorId,
                    name: name,
                    modelCode: model,
                    specs: specs,
                    moq: moq,
                    quotedPrice: price,
                    priceCurrency: currency,
                    leadTime: lead,
                    paymentTerms: terms,
                    shortlisted: shortlisted,
                    rating: rating,
                  ).toMap()
                    ..remove('id'),
                );
                _load();
                if (!mounted) return;
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddContactSheet(int exhibitorId) async {
    final formKey = GlobalKey<FormState>();
    String name = 'Contact';
    String designation = '';
    String phone = '';
    String email = '';
    String whatsapp = '';
    String wechat = '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Contact Name'),
                    onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Designation'),
                    onSaved: (v) => designation = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Phone'),
                    onSaved: (v) => phone = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Email'),
                    onSaved: (v) => email = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'WhatsApp'),
                    onSaved: (v) => whatsapp = v?.trim() ?? ''),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'WeChat'),
                    onSaved: (v) => wechat = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              formKey.currentState?.save();
              final dbx = await TradeDatabase.instance.database;
              if (phone.trim().isNotEmpty) {
                final existing = await dbx.query(
                  'contacts',
                  where: 'exhibitor_id = ? AND phone = ?',
                  whereArgs: [exhibitorId, phone.trim()],
                );
                if (existing.isNotEmpty && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('Same phone already exists for this supplier')));
                }
              }
              await dbx.insert(
                  'contacts',
                  Contact(
                    exhibitorId: exhibitorId,
                    name: name,
                    designation: designation,
                    phone: phone,
                    email: email,
                    whatsapp: whatsapp,
                    wechat: wechat,
                  ).toMap());
              _load();
              if (!mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddProductSheet(int exhibitorId) async {
    final formKey = GlobalKey<FormState>();
    String name = 'Product';
    String model = '';
    String specs = '';
    String currency = 'USD';
    double? moq;
    double? price;
    String lead = '';
    String terms = '';
    bool shortlisted = false;
    int rating = 0;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Add Product'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextFormField(
                      decoration:
                          const InputDecoration(labelText: 'Product Name'),
                      onSaved: (v) => name = v?.trim() ?? name),
                  TextFormField(
                      decoration:
                          const InputDecoration(labelText: 'Model / SKU'),
                      onSaved: (v) => model = v?.trim() ?? ''),
                  TextFormField(
                      decoration: const InputDecoration(labelText: 'Specs'),
                      onSaved: (v) => specs = v?.trim() ?? ''),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'MOQ'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setStateDialog(() => moq = double.tryParse(v)),
                    onSaved: (v) => moq = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Quoted price'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        setStateDialog(() => price = double.tryParse(v)),
                    onSaved: (v) => price = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                      decoration: const InputDecoration(labelText: 'Currency'),
                      onSaved: (v) => currency = v?.trim() ?? 'USD'),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Lead time'),
                    onChanged: (v) => setStateDialog(() => lead = v.trim()),
                    onSaved: (v) => lead = v?.trim() ?? '',
                  ),
                  TextFormField(
                      decoration:
                          const InputDecoration(labelText: 'Payment terms'),
                      onSaved: (v) => terms = v?.trim() ?? ''),
                  DropdownButtonFormField<int>(
                    value: rating,
                    items: List.generate(
                      6,
                      (i) =>
                          DropdownMenuItem(value: i, child: Text('Rating $i')),
                    ),
                    onChanged: (v) => setStateDialog(() => rating = v ?? 0),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Live shortlist score: ${_productShortlistScoreForValues(rating: rating, quotedPrice: price, moq: moq, leadTime: lead).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: shortlisted,
                    title: const Text('Shortlist this product'),
                    onChanged: (v) =>
                        setStateDialog(() => shortlisted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                formKey.currentState?.save();
                final dbi = await TradeDatabase.instance.database;
                await dbi.insert(
                  'products',
                  Product(
                    exhibitorId: exhibitorId,
                    name: name,
                    modelCode: model,
                    specs: specs,
                    moq: moq,
                    quotedPrice: price,
                    priceCurrency: currency,
                    leadTime: lead,
                    paymentTerms: terms,
                    shortlisted: shortlisted,
                    rating: rating,
                  ).toMap(),
                );
                _load();
                if (!mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMeetingSheet(int exhibitorId) async {
    final formKey = GlobalKey<FormState>();
    DateTime meeting = DateTime.now();
    DateTime? followUp;
    String outcome = 'Interested';
    String priority = 'Medium';
    String notes = '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Meeting / Follow-up'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'Meeting date (YYYY-MM-DD HH:mm)'),
                  onSaved: (v) {
                    if (v != null && v.isNotEmpty) {
                      try {
                        final parsed = DateTime.parse(v);
                        meeting = parsed;
                      } catch (_) {}
                    }
                  },
                ),
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'Follow-up date (YYYY-MM-DD HH:mm)'),
                  onSaved: (v) {
                    if (v != null && v.isNotEmpty) {
                      try {
                        followUp = DateTime.parse(v);
                      } catch (_) {
                        followUp = null;
                      }
                    }
                  },
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Outcome'),
                  onSaved: (v) => outcome = v?.trim() ?? 'Interested',
                ),
                DropdownButtonFormField<String>(
                  value: priority,
                  items: const [
                    DropdownMenuItem(value: 'High', child: Text('High')),
                    DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'Low', child: Text('Low')),
                  ],
                  onChanged: (v) => priority = v ?? 'Medium',
                ),
                TextFormField(
                    decoration: const InputDecoration(labelText: 'Notes'),
                    onSaved: (v) => notes = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              formKey.currentState?.save();
              final dbi = await TradeDatabase.instance.database;
              final meetingId = await dbi.insert(
                  'meetings',
                  Meeting(
                    exhibitorId: exhibitorId,
                    meetingDate: meeting,
                    followUpDate: followUp,
                    outcome: outcome,
                    priority: priority,
                    notes: notes,
                  ).toMap());
              if (followUp != null) {
                await ReminderService.scheduleFollowUp(
                  id: meetingId,
                  title: 'Supplier follow-up is due',
                  body:
                      'Follow-up scheduled for outcome: $outcome (${priority})',
                  at: followUp!,
                );
              }
              _load();
              if (!mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleProductShortlist(Product p) async {
    await db.update('products', p.id!, {'shortlisted': p.shortlisted ? 0 : 1});
    _load();
  }

  double _productShortlistScoreForValues({
    required int rating,
    double? quotedPrice,
    double? moq,
    String leadTime = '',
  }) {
    final ratingScore = (rating / 5.0) * 40.0;
    final priceScore =
        quotedPrice == null ? 0.0 : 1000.0 / (1.0 + quotedPrice.abs());
    final moqScore = moq == null ? 0.0 : 30.0 / (1.0 + moq);
    final leadMatch = RegExp(r'\d+').firstMatch(leadTime);
    final lead =
        leadMatch == null ? null : double.tryParse(leadMatch.group(0)!);
    final leadScore = lead == null ? 0.0 : 15.0 / (1.0 + lead);
    return ratingScore + priceScore + moqScore + leadScore;
  }

  static const _messageTemplates = [
    'Hi {name}, nice meeting you at Canton Fair. Thank you for sharing product details.',
    'Hi {name}, can you please send the latest official quotation and sample photos for {company}?',
    'Hi {name}, could you share MOQ, lead time, and payment terms for {product} please?',
    'Hi {name}, we are finalizing suppliers and would like to schedule sample shipment discussion.',
  ];

  Future<void> _openAttachmentPicker({
    required int ownerId,
    required String ownerType,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked == null || !mounted) return;

    final root = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${root.path}/attachments/$ownerType/$ownerId');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final extensionIndex = picked.path.lastIndexOf('.');
    final extension =
        extensionIndex >= 0 ? picked.path.substring(extensionIndex) : '.jpg';
    final fileName =
        'attachment_${DateTime.now().millisecondsSinceEpoch}$extension';
    final saved = await File(picked.path).copy('${targetDir.path}/$fileName');
    await db.addAttachment(
      Attachment(
        ownerType: ownerType,
        ownerId: ownerId,
        kind: 'image',
        path: saved.path,
        note: 'Photo',
        createdAt: DateTime.now(),
      ),
    );
    _load();
  }

  Future<void> _openAttachment(String path) async {
    if (await canLaunchUrl(Uri.parse('file://$path'))) {
      await launchUrl(Uri.parse('file://$path'),
          mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attachment file'),
        content: path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg') ||
                path.toLowerCase().endsWith('.png')
            ? Image.file(File(path), fit: BoxFit.contain)
            : const Text('This file is saved locally on the device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _openTemplateForContact(Contact c, Exhibitor e) async {
    final options = _messageTemplates
        .map((tpl) =>
            tpl.replaceAll('{name}', c.name).replaceAll('{company}', e.name))
        .toList();
    final message = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ...options.map(
              (tpl) => ListTile(
                title: Text(tpl),
                onTap: () => Navigator.pop(ctx, tpl),
              ),
            ),
          ],
        ),
      ),
    );
    if (message == null || !mounted) return;

    await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.phone),
              title: const Text('Copy message'),
              onTap: () async {
                await _copyText(message);
                if (!mounted) return;
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Send via WhatsApp'),
              onTap: () {
                Navigator.pop(ctx);
                _openWhatsAppTemplate(c, message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Send via Email'),
              onTap: () {
                Navigator.pop(ctx);
                _openEmailTemplate(c, e, message);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEmailTemplate(
      Contact c, Exhibitor e, String message) async {
    final subject =
        Uri.encodeComponent('Follow-up from Canton Fair: ${e.name}');
    final body = Uri.encodeComponent(message);
    await _launchAction(
        Uri.parse('mailto:${c.email}?subject=$subject&body=$body'));
  }

  Future<void> _openWhatsAppTemplate(Contact c, String message) async {
    final normalized =
        _digitsOnly(c.whatsapp.isNotEmpty ? c.whatsapp : c.phone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No WhatsApp number available')));
      return;
    }
    await _launchAction(Uri.parse(
        'https://wa.me/$normalized?text=${Uri.encodeComponent(message)}'));
  }

  Widget _attachmentSection(String ownerType, int ownerId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Attachments',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () =>
                  _openAttachmentPicker(ownerId: ownerId, ownerType: ownerType),
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add'),
            ),
          ],
        ),
        FutureBuilder<List<Attachment>>(
          future: db.getAttachments(ownerType, ownerId),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.isEmpty) {
              return const Text('No attachments yet');
            }
            return Wrap(
              spacing: 8,
              children: snap.data!.map((attachment) {
                return ActionChip(
                  avatar: const Icon(Icons.attachment, size: 16),
                  label:
                      Text(attachment.note.isEmpty ? 'Image' : attachment.note),
                  onPressed: () => _openAttachment(attachment.path),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _launchAction(Uri uri) async {
    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open ${uri.toString()}')));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  Future<void> _openWhatsApp(String phone) async {
    final normalized = _digitsOnly(phone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number to open WhatsApp')));
      return;
    }
    await _launchAction(Uri.parse('https://wa.me/$normalized'));
  }

  Future<void> _openCall(String phone) async {
    if (phone.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number to call')));
      return;
    }
    await _launchAction(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _openEmail(String email) async {
    if (email.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No email to open')));
      return;
    }
    await _launchAction(Uri.parse('mailto:$email'));
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Widget _contactRow(Contact c, Exhibitor e) {
    return Card(
      child: ListTile(
        title: Text('${c.name} (${c.designation})'),
        subtitle: Text(
          'Phone: ${c.phone.isEmpty ? "N/A" : c.phone} | Email: ${c.email.isEmpty ? "N/A" : c.email} | '
          'WeChat: ${c.wechat.isEmpty ? "N/A" : c.wechat}',
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _openEditContactSheet(c)),
            IconButton(
                icon: const Icon(Icons.call),
                onPressed: () => _openCall(c.phone)),
            IconButton(
                icon: const Icon(Icons.message),
                onPressed: () => _openWhatsApp(c.phone)),
            IconButton(
                icon: const Icon(Icons.email),
                onPressed: () => _openEmail(c.email)),
            IconButton(
              icon: const Icon(Icons.speaker_notes),
              onPressed: () => _openTemplateForContact(c, e),
              tooltip: 'Message templates',
            ),
            IconButton(
                icon: const Icon(Icons.copy_all),
                onPressed: () =>
                    _copyText(c.phone.isNotEmpty ? c.phone : c.email)),
          ],
        ),
      ),
    );
  }

  Widget _productRow(Product p) {
    return ListTile(
      title: Text('${p.name} (${p.modelCode})'),
      subtitle: Text(
        '${p.quotedPrice == null ? "No price" : "${p.quotedPrice} ${p.priceCurrency}"} | MOQ: ${p.moq ?? '-'} | Lead time: ${p.leadTime} | Score: ${_productShortlistScoreForValues(rating: p.rating, quotedPrice: p.quotedPrice, moq: p.moq, leadTime: p.leadTime).toStringAsFixed(2)}',
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            icon: Icon(
              p.shortlisted ? Icons.star : Icons.star_border,
              color: p.shortlisted ? Colors.amber : null,
            ),
            tooltip:
                p.shortlisted ? 'Remove from shortlist' : 'Add to shortlist',
            onPressed: () => _toggleProductShortlist(p),
          ),
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _openEditProductSheet(p)),
          IconButton(
            icon: const Icon(Icons.request_quote),
            tooltip: 'Add quote version',
            onPressed: () => _openAddQuoteDialog(p),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete product'),
                  content: const Text('Do you want to remove this product?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm != true) return;
              await db.delete('products', p.id!);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openSupplierScorecard(Exhibitor exhibitor) async {
    var quality = exhibitor.qualityScore;
    var responseSpeed = exhibitor.responseSpeedScore;
    var trust = exhibitor.trustScore;
    var moqFit = exhibitor.moqFitScore;
    var reliability = exhibitor.reliabilityScore;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget scoreField(
              String label, int value, ValueChanged<double> onChanged) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label),
                    Text('$value / 5',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                Slider(
                  value: value.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: '$value',
                  onChanged: onChanged,
                ),
              ],
            );
          }

          final decisionScore =
              (quality + responseSpeed + trust + moqFit + reliability) * 4;
          return AlertDialog(
            title: const Text('Supplier scorecard'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(exhibitor.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Decision score: $decisionScore / 100'),
                    const SizedBox(height: 12),
                    scoreField('Quality', quality,
                        (v) => setDialogState(() => quality = v.round())),
                    scoreField('Response speed', responseSpeed,
                        (v) => setDialogState(() => responseSpeed = v.round())),
                    scoreField('Trust', trust,
                        (v) => setDialogState(() => trust = v.round())),
                    scoreField('MOQ fit', moqFit,
                        (v) => setDialogState(() => moqFit = v.round())),
                    scoreField('Reliability', reliability,
                        (v) => setDialogState(() => reliability = v.round())),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  await db.update('exhibitors', exhibitor.id!, {
                    'quality_score': quality,
                    'response_speed_score': responseSpeed,
                    'trust_score': trust,
                    'moq_fit_score': moqFit,
                    'reliability_score': reliability,
                  });
                  _load();
                  if (!mounted) return;
                  Navigator.pop(ctx);
                },
                child: const Text('Save scorecard'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setVisited(Exhibitor exhibitor, bool visited) async {
    await db.update('exhibitors', exhibitor.id!, {
      'visited_at': visited ? DateTime.now().toIso8601String() : null,
    });
    _load();
  }

  Future<void> _openScheduleVisitDialog(Exhibitor exhibitor) async {
    var scheduledAt = exhibitor.plannedVisitAt?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Schedule supplier visit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exhibitor.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(
                    '${scheduledAt.year.toString().padLeft(4, '0')}-${scheduledAt.month.toString().padLeft(2, '0')}-${scheduledAt.day.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: scheduledAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  setDialogState(() => scheduledAt = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        scheduledAt.hour,
                        scheduledAt.minute,
                      ));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Time'),
                subtitle: Text(
                    '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(scheduledAt),
                  );
                  if (picked == null) return;
                  setDialogState(() => scheduledAt = DateTime(
                        scheduledAt.year,
                        scheduledAt.month,
                        scheduledAt.day,
                        picked.hour,
                        picked.minute,
                      ));
                },
              ),
            ],
          ),
          actions: [
            if (exhibitor.plannedVisitAt != null)
              TextButton(
                onPressed: () async {
                  await db.update('exhibitors', exhibitor.id!, {
                    'planned_visit_at': null,
                  });
                  _load();
                  if (!mounted) return;
                  Navigator.pop(ctx);
                },
                child: const Text('Clear schedule'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await db.update('exhibitors', exhibitor.id!, {
                  'planned_visit_at': scheduledAt.toIso8601String(),
                  'visited_at': null,
                });
                _load();
                if (!mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Save visit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddQuoteDialog(Product product) async {
    final formKey = GlobalKey<FormState>();
    var quoteType = 'Production';
    var currency = product.priceCurrency;
    var price = product.quotedPrice;
    var moq = product.moq;
    var validUntil = DateTime.now().add(const Duration(days: 30));
    var note = '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add quote version'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(product.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: quoteType,
                      decoration:
                          const InputDecoration(labelText: 'Quote type'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Sample', child: Text('Sample')),
                        DropdownMenuItem(
                            value: 'Production', child: Text('Production')),
                        DropdownMenuItem(value: 'Bulk', child: Text('Bulk')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => quoteType = value ?? quoteType),
                    ),
                    TextFormField(
                      initialValue: price?.toString() ?? '',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Unit price'),
                      onSaved: (value) =>
                          price = double.tryParse(value?.trim() ?? ''),
                    ),
                    TextFormField(
                      initialValue: currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      onSaved: (value) =>
                          currency = value?.trim().toUpperCase() ?? currency,
                    ),
                    TextFormField(
                      initialValue: moq?.toString() ?? '',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'MOQ'),
                      onSaved: (value) =>
                          moq = double.tryParse(value?.trim() ?? ''),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available),
                      title: const Text('Valid until'),
                      subtitle: Text(
                          '${validUntil.year.toString().padLeft(4, '0')}-${validUntil.month.toString().padLeft(2, '0')}-${validUntil.day.toString().padLeft(2, '0')}'),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: validUntil,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => validUntil = picked);
                        }
                      },
                    ),
                    TextFormField(
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Quote notes'),
                      onSaved: (value) => note = value?.trim() ?? '',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                formKey.currentState?.save();
                final quoteId = await db.insert(
                  'quotes',
                  Quote(
                    productId: product.id!,
                    label: quoteType,
                    unitPrice: price,
                    currency: currency.isEmpty ? 'USD' : currency,
                    moq: moq,
                    note: note,
                    validUntil: validUntil,
                    isSampleQuote: quoteType == 'Sample',
                  ).toMap()
                    ..remove('id'),
                );
                await db.update('products', product.id!, {
                  'quoted_price': price,
                  'price_currency': currency.isEmpty ? 'USD' : currency,
                  'moq': moq,
                });
                final reminderAt = validUntil.subtract(const Duration(days: 3));
                if (reminderAt.isAfter(DateTime.now())) {
                  await ReminderService.scheduleFollowUp(
                    id: 1000000 + quoteId,
                    title: 'Quote expires soon',
                    body: '${product.name} $quoteType quote expires in 3 days.',
                    at: reminderAt,
                  );
                }
                _load();
                if (!mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Save quote'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isQuoteExpired(Quote quote) =>
      quote.validUntil != null && quote.validUntil!.isBefore(DateTime.now());

  bool _isQuoteExpiring(Quote quote) {
    if (quote.validUntil == null || _isQuoteExpired(quote)) return false;
    return quote.validUntil!
        .isBefore(DateTime.now().add(const Duration(days: 8)));
  }

  Widget _quoteHistory(Product product) {
    return FutureBuilder<List<Quote>>(
      future: db.getQuotes(product.id!),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.request_quote),
              label: const Text('Add first quote'),
              onPressed: () => _openAddQuoteDialog(product),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Quote history',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Version'),
                    onPressed: () => _openAddQuoteDialog(product),
                  ),
                ],
              ),
              ...snapshot.data!.map((quote) {
                final expired = _isQuoteExpired(quote);
                final expiring = _isQuoteExpiring(quote);
                final color = expired
                    ? AppColors.danger
                    : expiring
                        ? AppColors.amber
                        : AppColors.teal;
                final status = expired
                    ? 'Expired'
                    : expiring
                        ? 'Expires soon'
                        : quote.validUntil == null
                            ? 'No expiry'
                            : 'Active';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.request_quote, color: color),
                  title: Text(
                      '${quote.label} | ${quote.unitPrice ?? '-'} ${quote.currency}'),
                  subtitle: Text(
                    'MOQ ${quote.moq ?? '-'} | Valid ${quote.validUntil == null ? '-' : quote.validUntil!.toLocal().toString().substring(0, 10)}${quote.note.isEmpty ? '' : ' | ${quote.note}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: InfoChip(label: status, color: color),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _changeItineraryDate(int days) {
    _itineraryDate = _itineraryDate.add(Duration(days: days));
    _load();
  }

  Widget _exhibitorActions(Exhibitor e) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'contact') {
          await _openAddContactSheet(e.id!);
        } else if (value == 'product') {
          await _openAddProductSheet(e.id!);
        } else if (value == 'meeting') {
          await _openMeetingSheet(e.id!);
        } else if (value == 'attachment') {
          await _openAttachmentPicker(ownerId: e.id!, ownerType: 'exhibitor');
        } else if (value == 'edit') {
          await _openEditExhibitorSheet(e);
        } else if (value == 'scorecard') {
          await _openSupplierScorecard(e);
        } else if (value == 'visited') {
          await _setVisited(e, true);
        } else if (value == 'needVisit') {
          await _setVisited(e, false);
        } else if (value == 'scheduleVisit') {
          await _openScheduleVisitDialog(e);
        } else if (value == 'merge') {
          await _openMergeDuplicateDialog(e);
        } else if (value == 'delete') {
          await _openDeleteExhibitorDialog(e);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit supplier')),
        PopupMenuItem(value: 'scorecard', child: Text('Supplier scorecard')),
        PopupMenuItem(value: 'visited', child: Text('Mark visited now')),
        PopupMenuItem(value: 'needVisit', child: Text('Move to need-to-visit')),
        PopupMenuItem(value: 'scheduleVisit', child: Text('Schedule visit')),
        PopupMenuItem(value: 'merge', child: Text('Merge duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete supplier')),
        PopupMenuItem(value: 'contact', child: Text('Add contact')),
        PopupMenuItem(value: 'product', child: Text('Add product')),
        PopupMenuItem(value: 'meeting', child: Text('Add meeting')),
        PopupMenuItem(value: 'attachment', child: Text('Add attachment')),
      ],
    );
  }

  Widget _visitQueueSection() {
    return FutureBuilder<_VisitQueues>(
      future: _visitQueues,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SectionPanel(
            title: 'Visit queues',
            child: SizedBox(
                height: 56, child: Center(child: CircularProgressIndicator())),
          );
        }
        final queues = snapshot.data!;
        return SectionPanel(
          title: 'Visit queues',
          subtitle:
              'Plan booth visits, then mark suppliers visited as you meet them.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricPill(
                      label: 'Need to visit',
                      value: queues.needToVisit.length.toString(),
                      icon: Icons.route_outlined,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricPill(
                      label: 'Visited today',
                      value: queues.visitedToday.length.toString(),
                      icon: Icons.task_alt,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
              if (queues.needToVisit.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...queues.needToVisit.take(5).map(
                      (supplier) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_on_outlined,
                            color: AppColors.amber),
                        title: Text(supplier.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          supplier.plannedVisitAt == null
                              ? 'Booth ${supplier.booth.isEmpty ? '-' : supplier.booth}'
                              : 'Planned ${supplier.plannedVisitAt!.toLocal().toString().substring(0, 16)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Mark visited',
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () => _setVisited(supplier, true),
                        ),
                      ),
                    ),
              ],
              if (queues.visitedToday.isNotEmpty) ...[
                const Divider(height: 22),
                ...queues.visitedToday.take(5).map(
                      (supplier) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle,
                            color: AppColors.teal),
                        title: Text(supplier.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            'Visited ${supplier.visitedAt!.toLocal().toString().substring(11, 16)}'),
                        trailing: IconButton(
                          tooltip: 'Move to need-to-visit',
                          icon: const Icon(Icons.undo),
                          onPressed: () => _setVisited(supplier, false),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _itinerarySection() {
    final dateLabel =
        '${_itineraryDate.year.toString().padLeft(4, '0')}-${_itineraryDate.month.toString().padLeft(2, '0')}-${_itineraryDate.day.toString().padLeft(2, '0')}';
    return SectionPanel(
      title: 'Day itinerary',
      subtitle: 'Scheduled supplier visits for the selected day.',
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _changeItineraryDate(-1),
              ),
              Expanded(
                child: Text(dateLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeItineraryDate(1),
              ),
              TextButton(
                onPressed: () {
                  _itineraryDate = DateTime.now();
                  _load();
                },
                child: const Text('Today'),
              ),
            ],
          ),
          FutureBuilder<List<Exhibitor>>(
            future: _itinerary,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No supplier visits are scheduled for this day.',
                      style: TextStyle(color: AppColors.muted)),
                );
              }
              return Column(
                children: snapshot.data!.map((supplier) {
                  final scheduled = supplier.plannedVisitAt!.toLocal();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    title: Text(supplier.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        'Booth ${supplier.booth.isEmpty ? '-' : supplier.booth}${supplier.hall.isEmpty ? '' : ' | ${supplier.hall}'}'),
                    trailing: IconButton(
                      tooltip: 'Reschedule',
                      icon: const Icon(Icons.edit_calendar),
                      onPressed: () => _openScheduleVisitDialog(supplier),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Exhibitor>>(
      future: _exhibitors,
      builder: (context, snapshot) {
        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: EnterprisePage(
            title: 'Supplier Capture',
            subtitle:
                'Create trips, capture supplier details, scan badges, and manage booth follow-through.',
            actions: [
              ElevatedButton.icon(
                  onPressed: _openAddExhibitorSheet,
                  icon: const Icon(Icons.business),
                  label: const Text('Supplier')),
              TextButton.icon(
                  onPressed: _openAddTripSheet,
                  icon: const Icon(Icons.flight_takeoff),
                  label: const Text('Trip')),
              TextButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('QR')),
              TextButton.icon(
                  onPressed: _openOcrCapture,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('OCR')),
            ],
            children: [
              _visitQueueSection(),
              const SizedBox(height: 16),
              _itinerarySection(),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'Filters',
                subtitle:
                    'Narrow records by trip, shortlist status, supplier, booth, or category.',
                child: Column(
                  children: [
                    FutureBuilder<List<Trip>>(
                      future: _trips,
                      builder: (_, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        return DropdownButtonFormField<int?>(
                          value: _tripFilter,
                          decoration: const InputDecoration(labelText: 'Trip'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('All trips')),
                            ...snap.data!.where((t) => t.id != null).map(
                                  (t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(t.name,
                                          overflow: TextOverflow.ellipsis)),
                                ),
                          ],
                          onChanged: (v) {
                            _tripFilter = v;
                            _load();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search supplier, booth, or category',
                      ),
                      onChanged: (v) {
                        _query = v.trim();
                        _load();
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          avatar: const Icon(Icons.star, size: 18),
                          label: const Text('Shortlist only'),
                          selected: _shortlistOnly,
                          onSelected: (v) {
                            _shortlistOnly = v;
                            _load();
                          },
                        ),
                        TextButton.icon(
                          onPressed: _tripFilter == null
                              ? null
                              : () => _openCloseTripSheet(_tripFilter!),
                          icon: const Icon(Icons.lock_clock),
                          label: const Text('Close trip'),
                        ),
                        TextButton.icon(
                          onPressed: _tripFilter == null
                              ? null
                              : () => _openDeleteTripDialog(_tripFilter!),
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Delete trip'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!snapshot.hasData)
                const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()))
              else if (snapshot.data!.isEmpty)
                const EmptyState(
                  icon: Icons.business_outlined,
                  title: 'No suppliers yet',
                  message: 'Add a trip and capture your first supplier visit.',
                )
              else
                ...snapshot.data!.map((e) => _supplierCard(e)),
            ],
          ),
        );
      },
    );
  }

  Widget _supplierCard(Exhibitor e) {
    final tags = e.tags.join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                InfoChip(
                    label: e.booth.isEmpty ? 'No booth' : e.booth,
                    icon: Icons.place),
                if (e.hall.isNotEmpty)
                  InfoChip(
                      label: e.hall,
                      icon: Icons.location_city,
                      color: AppColors.teal),
                if (e.category.isNotEmpty)
                  InfoChip(
                      label: e.category,
                      icon: Icons.category,
                      color: const Color(0xFF6B4E9B)),
                if (e.country.isNotEmpty)
                  InfoChip(
                      label: e.country,
                      icon: Icons.flag,
                      color: AppColors.amber),
                if (e.shortlisted)
                  const InfoChip(
                      label: 'Shortlisted',
                      icon: Icons.star,
                      color: Color(0xFF2F855A)),
                InfoChip(
                  label: e.visitedAt == null ? 'Need to visit' : 'Visited',
                  icon: e.visitedAt == null
                      ? Icons.route_outlined
                      : Icons.task_alt,
                  color: e.visitedAt == null ? AppColors.amber : AppColors.teal,
                ),
              ],
            ),
          ),
          trailing: _exhibitorActions(e),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                e.contactCompanyNotes.isEmpty
                    ? 'No supplier notes recorded.'
                    : e.contactCompanyNotes,
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tags.isEmpty ? 'No tags' : tags,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<Contact>>(
              future: db.getContacts(e.id!),
              builder: (ctx, cSnap) {
                if (!cSnap.hasData || cSnap.data!.isEmpty)
                  return const Text('No contacts yet');
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        cSnap.data!.map((c) => _contactRow(c, e)).toList());
              },
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Product>>(
              future: db.getProducts(e.id!),
              builder: (ctx, pSnap) {
                if (!pSnap.hasData || pSnap.data!.isEmpty)
                  return const Text('No products yet');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: pSnap.data!.expand((p) {
                    return [
                      _productRow(p),
                      _quoteHistory(p),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _attachmentSection('product', p.id ?? 0),
                      ),
                    ];
                  }).toList(),
                );
              },
            ),
            _attachmentSection('exhibitor', e.id!),
          ],
        ),
      ),
    );
  }
}
