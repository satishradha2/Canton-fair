import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';
import 'scanner_screen.dart';
import 'ocr_screen.dart';

class CapturesScreen extends StatefulWidget {
  const CapturesScreen({super.key});

  @override
  State<CapturesScreen> createState() => _CapturesScreenState();
}

class _CapturesScreenState extends State<CapturesScreen> {
  final db = TradeDatabase.instance;
  int? _tripFilter;
  String _query = '';
  bool _shortlistOnly = false;
  late Future<List<Trip>> _trips;
  late Future<List<Exhibitor>> _exhibitors;

  @override
  void initState() {
    super.initState();
    _trips = db.getTrips();
    _load();
  }

  void _load() {
    setState(() {
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

  Future<List<Exhibitor>> _getDuplicateCandidates(Exhibitor candidate) async {
    final rows = await db.getExhibitors(null);
    return rows.where((e) {
      final sameName = e.name.toLowerCase().trim() == candidate.name.toLowerCase().trim();
      final sameBooth = e.booth.isNotEmpty &&
          e.booth.toLowerCase().trim() == candidate.booth.toLowerCase().trim();
      final boothMatch = e.booth.isNotEmpty && candidate.booth.isNotEmpty && sameBooth;
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
    final lines = input.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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
    final simple = input.split(RegExp(r'[;,\r\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (simple.isNotEmpty) {
      map['name'] = simple[0];
      if (simple.length > 1) map['booth'] = simple[1];
      if (simple.length > 2) map['country'] = simple[2];
    }
    return map;
  }

  Future<void> _openScanner() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (value == null || value.trim().isEmpty) return;
    final parsed = await _parseScannerPayload(value);
    await _openAddExhibitorSheet(prefill: parsed);
    if (!mounted) return;
  }

  Future<void> _openOcrCapture() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const OcrScreen()));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            child: const Text('Mark closed'),
            onPressed: () async {
              await db.closeTrip(tripId, note: noteController.text.trim());
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Trip "${trip.name}" has been marked closed')),
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
                  decoration: const InputDecoration(labelText: 'Start date YYYY-MM-DD'),
                  onSaved: (v) => start = v?.trim() ?? '',
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'End date YYYY-MM-DD'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
    String category = seed['category']?.isNotEmpty == true ? seed['category']! : '';
    String country = seed['country']?.isNotEmpty == true ? seed['country']! : '';
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
                TextFormField(decoration: const InputDecoration(labelText: 'Supplier Name'), onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(decoration: const InputDecoration(labelText: 'Booth'), onSaved: (v) => booth = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Hall'), onSaved: (v) => hall = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Category'), onSaved: (v) => category = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Country'), onSaved: (v) => country = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Company notes'), onSaved: (v) => notes = v?.trim() ?? ''),
                DropdownButtonFormField<int>(
                  value: rating,
                  items: List.generate(
                    6,
                    (i) => DropdownMenuItem(value: i, child: Text('Rating $i')),
                  ),
                  onChanged: (v) => rating = v ?? 0,
                  decoration: const InputDecoration(labelText: 'Initial rating'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
        content: Text('Delete "${trip.name}" and all linked exhibitors, products, contacts, meetings, and attachments?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trip "${trip.name}" deleted')));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                    subtitle: Text('Booth: ${it.booth} | Country: ${it.country}'),
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
        content: const Text('Move all contacts, products, and history to selected supplier and delete duplicate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Merge')),
        ],
      ),
    );
    if (confirm != true) return;

    await db.mergeExhibitorRecords(targetId, source.id!);
    if (!mounted) return;
      _load();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicate merged successfully.')));
  }

  Future<void> _openDeleteExhibitorDialog(Exhibitor e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete supplier'),
        content: const Text('Delete supplier and all linked products, contacts, meetings, and attachments?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Supplier "${e.name}" deleted')));
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
                TextFormField(initialValue: name, decoration: const InputDecoration(labelText: 'Contact Name'), onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(initialValue: designation, decoration: const InputDecoration(labelText: 'Designation'), onSaved: (v) => designation = v?.trim() ?? ''),
                TextFormField(initialValue: phone, decoration: const InputDecoration(labelText: 'Phone'), onSaved: (v) => phone = v?.trim() ?? ''),
                TextFormField(initialValue: email, decoration: const InputDecoration(labelText: 'Email'), onSaved: (v) => email = v?.trim() ?? ''),
                TextFormField(initialValue: whatsapp, decoration: const InputDecoration(labelText: 'WhatsApp'), onSaved: (v) => whatsapp = v?.trim() ?? ''),
                TextFormField(initialValue: wechat, decoration: const InputDecoration(labelText: 'WeChat'), onSaved: (v) => wechat = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                  TextFormField(initialValue: name, decoration: const InputDecoration(labelText: 'Product Name'), onSaved: (v) => name = v?.trim() ?? name),
                  TextFormField(initialValue: model, decoration: const InputDecoration(labelText: 'Model / SKU'), onSaved: (v) => model = v?.trim() ?? ''),
                  TextFormField(initialValue: specs, decoration: const InputDecoration(labelText: 'Specs'), onSaved: (v) => specs = v?.trim() ?? ''),
                  TextFormField(
                    initialValue: p.moq?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'MOQ'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setStateDialog(() => moq = double.tryParse(v)),
                    onSaved: (v) => moq = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                    initialValue: p.quotedPrice?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'Quoted price'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setStateDialog(() => price = double.tryParse(v)),
                    onSaved: (v) => price = double.tryParse(v ?? ''),
                  ),
                  TextFormField(initialValue: currency, decoration: const InputDecoration(labelText: 'Currency'), onSaved: (v) => currency = v?.trim() ?? 'USD'),
                  TextFormField(
                    initialValue: lead,
                    decoration: const InputDecoration(labelText: 'Lead time'),
                    onChanged: (v) => setStateDialog(() => lead = v?.trim() ?? ''),
                    onSaved: (v) => lead = v?.trim() ?? '',
                  ),
                  TextFormField(initialValue: terms, decoration: const InputDecoration(labelText: 'Payment terms'), onSaved: (v) => terms = v?.trim() ?? ''),
                  DropdownButtonFormField<int>(
                    value: rating,
                    items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text('Rating $i'))),
                    onChanged: (v) => setStateDialog(() => rating = v ?? 0),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Live shortlist score: ${_productShortlistScoreForValues(rating: rating, quotedPrice: price, moq: moq, leadTime: lead).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: shortlisted,
                    title: const Text('Shortlist this product'),
                    onChanged: (v) => setStateDialog(() => shortlisted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                TextFormField(decoration: const InputDecoration(labelText: 'Contact Name'), onSaved: (v) => name = v?.trim() ?? name),
                TextFormField(decoration: const InputDecoration(labelText: 'Designation'), onSaved: (v) => designation = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Phone'), onSaved: (v) => phone = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'Email'), onSaved: (v) => email = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'WhatsApp'), onSaved: (v) => whatsapp = v?.trim() ?? ''),
                TextFormField(decoration: const InputDecoration(labelText: 'WeChat'), onSaved: (v) => wechat = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Same phone already exists for this supplier')));
                }
              }
              await dbx.insert('contacts', Contact(
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
                  TextFormField(decoration: const InputDecoration(labelText: 'Product Name'), onSaved: (v) => name = v?.trim() ?? name),
                  TextFormField(decoration: const InputDecoration(labelText: 'Model / SKU'), onSaved: (v) => model = v?.trim() ?? ''),
                  TextFormField(decoration: const InputDecoration(labelText: 'Specs'), onSaved: (v) => specs = v?.trim() ?? ''),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'MOQ'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setStateDialog(() => moq = double.tryParse(v)),
                    onSaved: (v) => moq = double.tryParse(v ?? ''),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Quoted price'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setStateDialog(() => price = double.tryParse(v)),
                    onSaved: (v) => price = double.tryParse(v ?? ''),
                  ),
                  TextFormField(decoration: const InputDecoration(labelText: 'Currency'), onSaved: (v) => currency = v?.trim() ?? 'USD'),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Lead time'),
                    onChanged: (v) => setStateDialog(() => lead = v?.trim() ?? ''),
                    onSaved: (v) => lead = v?.trim() ?? '',
                  ),
                  TextFormField(decoration: const InputDecoration(labelText: 'Payment terms'), onSaved: (v) => terms = v?.trim() ?? ''),
                  DropdownButtonFormField<int>(
                    value: rating,
                    items: List.generate(
                      6,
                      (i) => DropdownMenuItem(value: i, child: Text('Rating $i')),
                    ),
                    onChanged: (v) => setStateDialog(() => rating = v ?? 0),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Live shortlist score: ${_productShortlistScoreForValues(rating: rating, quotedPrice: price, moq: moq, leadTime: lead).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: shortlisted,
                    title: const Text('Shortlist this product'),
                    onChanged: (v) => setStateDialog(() => shortlisted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                  decoration: const InputDecoration(labelText: 'Meeting date (YYYY-MM-DD HH:mm)'),
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
                  decoration: const InputDecoration(labelText: 'Follow-up date (YYYY-MM-DD HH:mm)'),
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
                TextFormField(decoration: const InputDecoration(labelText: 'Notes'), onSaved: (v) => notes = v?.trim() ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              formKey.currentState?.save();
              final dbi = await TradeDatabase.instance.database;
              final meetingId = await dbi.insert('meetings', Meeting(
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
                  body: 'Follow-up scheduled for outcome: $outcome (${priority})',
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
    final priceScore = quotedPrice == null ? 0.0 : 1000.0 / (1.0 + quotedPrice.abs());
    final moqScore = moq == null ? 0.0 : 30.0 / (1.0 + moq);
    final leadMatch = RegExp(r'\d+').firstMatch(leadTime);
    final lead = leadMatch == null ? null : double.tryParse(leadMatch.group(0)!);
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
    final extension = extensionIndex >= 0 ? picked.path.substring(extensionIndex) : '.jpg';
    final fileName = 'attachment_${DateTime.now().millisecondsSinceEpoch}$extension';
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
      await launchUrl(Uri.parse('file://$path'), mode: LaunchMode.externalApplication);
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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _openTemplateForContact(Contact c, Exhibitor e) async {
    final options = _messageTemplates.map((tpl) => tpl.replaceAll('{name}', c.name).replaceAll('{company}', e.name)).toList();
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

  Future<void> _openEmailTemplate(Contact c, Exhibitor e, String message) async {
    final subject = Uri.encodeComponent('Follow-up from Canton Fair: ${e.name}');
    final body = Uri.encodeComponent(message);
    await _launchAction(Uri.parse('mailto:${c.email}?subject=$subject&body=$body'));
  }

  Future<void> _openWhatsAppTemplate(Contact c, String message) async {
    final normalized = _digitsOnly(c.whatsapp.isNotEmpty ? c.whatsapp : c.phone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No WhatsApp number available')));
      return;
    }
    await _launchAction(Uri.parse('https://wa.me/$normalized?text=${Uri.encodeComponent(message)}'));
  }

  Widget _attachmentSection(String ownerType, int ownerId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Attachments', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openAttachmentPicker(ownerId: ownerId, ownerType: ownerType),
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
                  label: Text(attachment.note.isEmpty ? 'Image' : attachment.note),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot open ${uri.toString()}')));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  Future<void> _openWhatsApp(String phone) async {
    final normalized = _digitsOnly(phone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number to open WhatsApp')));
      return;
    }
    await _launchAction(Uri.parse('https://wa.me/$normalized'));
  }

  Future<void> _openCall(String phone) async {
    if (phone.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number to call')));
      return;
    }
    await _launchAction(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _openEmail(String email) async {
    if (email.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email to open')));
      return;
    }
    await _launchAction(Uri.parse('mailto:$email'));
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
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
            IconButton(icon: const Icon(Icons.edit), onPressed: () => _openEditContactSheet(c)),
            IconButton(icon: const Icon(Icons.call), onPressed: () => _openCall(c.phone)),
            IconButton(icon: const Icon(Icons.message), onPressed: () => _openWhatsApp(c.phone)),
            IconButton(icon: const Icon(Icons.email), onPressed: () => _openEmail(c.email)),
            IconButton(
              icon: const Icon(Icons.speaker_notes),
              onPressed: () => _openTemplateForContact(c, e),
              tooltip: 'Message templates',
            ),
            IconButton(icon: const Icon(Icons.copy_all), onPressed: () => _copyText(c.phone.isNotEmpty ? c.phone : c.email)),
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
            tooltip: p.shortlisted ? 'Remove from shortlist' : 'Add to shortlist',
            onPressed: () => _toggleProductShortlist(p),
          ),
          IconButton(icon: const Icon(Icons.edit), onPressed: () => _openEditProductSheet(p)),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete product'),
                  content: const Text('Do you want to remove this product?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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
        } else if (value == 'merge') {
          await _openMergeDuplicateDialog(e);
        } else if (value == 'delete') {
          await _openDeleteExhibitorDialog(e);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit supplier')),
        PopupMenuItem(value: 'merge', child: Text('Merge duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete supplier')),
        PopupMenuItem(value: 'contact', child: Text('Add contact')),
        PopupMenuItem(value: 'product', child: Text('Add product')),
        PopupMenuItem(value: 'meeting', child: Text('Add meeting')),
        PopupMenuItem(value: 'attachment', child: Text('Add attachment')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Exhibitor>>(
      future: _exhibitors,
      builder: (context, snapshot) {
        return Scaffold(
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'trip',
                onPressed: _openAddTripSheet,
                icon: const Icon(Icons.flight_takeoff),
                label: const Text('Add Trip'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'ex',
                onPressed: _openAddExhibitorSheet,
                icon: const Icon(Icons.business),
                label: const Text('Add Supplier'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'scan',
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'ocr',
                onPressed: _openOcrCapture,
                icon: const Icon(Icons.document_scanner),
                label: const Text('OCR Card'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                    Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<List<Trip>>(
                        future: _trips,
                        builder: (_, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          return DropdownButtonFormField<int?>(
                            value: _tripFilter,
                            decoration: const InputDecoration(labelText: 'Trip'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Trips')),
                              ...snap.data!
                                  .where((t) => t.id != null)
                                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                            ],
                            onChanged: (v) {
                              _tripFilter = v;
                              _load();
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _tripFilter == null ? null : () => _openCloseTripSheet(_tripFilter!),
                      icon: const Icon(Icons.lock_clock),
                      label: const Text('Close trip'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _tripFilter == null ? null : () => _openDeleteTripDialog(_tripFilter!),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete trip'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: CheckboxListTile(
                        value: _shortlistOnly,
                        title: const Text('Shortlist only'),
                        onChanged: (v) {
                          _shortlistOnly = v ?? false;
                          _load();
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search supplier / booth / category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) {
                    _query = v.trim();
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if (!snapshot.hasData) const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
                else if (snapshot.data!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No suppliers yet. Add your first visit and supplier.'),
                  )
                else
                  ...snapshot.data!.map(
                    (e) => Card(
                      child: ExpansionTile(
                        title: Text('${e.name}  (${e.booth.isEmpty ? 'No booth' : e.booth})'),
                        subtitle: Text(
                          'Hall: ${e.hall}  |  Category: ${e.category}  |  Country: ${e.country}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (e.shortlisted) const Icon(Icons.star, color: Colors.amber),
                            _exhibitorActions(e),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Notes: ${e.contactCompanyNotes}'),
                                const SizedBox(height: 8),
                                Text(
                                  'Tags: ${e.tags.join(", ").isEmpty ? "No tags" : e.tags.join(", ")}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                FutureBuilder<List<Contact>>(
                                  future: db.getContacts(e.id!),
                                  builder: (ctx, cSnap) {
                                    if (!cSnap.hasData || cSnap.data!.isEmpty) {
                                      return const Text('No contacts yet');
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: cSnap.data!.map((c) => _contactRow(c, e)).toList(),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                FutureBuilder<List<Product>>(
                                  future: db.getProducts(e.id!),
                                  builder: (ctx, pSnap) {
                                    if (!pSnap.hasData || pSnap.data!.isEmpty) {
                                      return const Text('No products yet');
                                    }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: pSnap.data!.expand((p) {
                                    return [
                                      _productRow(p),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 16),
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
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
