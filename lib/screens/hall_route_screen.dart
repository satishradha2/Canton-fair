import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class HallRouteScreen extends StatefulWidget {
  const HallRouteScreen({super.key});

  @override
  State<HallRouteScreen> createState() => _HallRouteScreenState();
}

class _HallRouteScreenState extends State<HallRouteScreen> {
  static const _mapPathKey = 'hall_route_map_path';
  final _db = TradeDatabase.instance;
  final _storage = const FlutterSecureStorage();
  int? _tripId;
  String? _mapPath;
  late Future<List<Trip>> _trips;
  late Future<List<Exhibitor>> _suppliers;

  @override
  void initState() {
    super.initState();
    _trips = _db.getTrips();
    _suppliers = _db.getExhibitors(null);
    _loadMap();
  }

  Future<void> _loadMap() async {
    final stored = await _storage.read(key: _mapPathKey);
    if (!mounted) return;
    setState(() => _mapPath = stored);
  }

  Future<void> _importMap() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null) return;
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/hall-maps');
    await directory.create(recursive: true);
    final destination =
        '${directory.path}/fair-map-${DateTime.now().millisecondsSinceEpoch}${path.extension(picked.path)}';
    await File(picked.path).copy(destination);
    await _storage.write(key: _mapPathKey, value: destination);
    if (mounted) setState(() => _mapPath = destination);
  }

  void _selectTrip(int? tripId) {
    setState(() {
      _tripId = tripId;
      _suppliers = _db.getExhibitors(tripId);
    });
  }

  int _routeWeight(Exhibitor supplier) {
    if (supplier.shortlisted) return 0;
    if (supplier.rating >= 4) return 1;
    if (supplier.visitedAt == null) return 2;
    return 3;
  }

  bool _isMissed(Exhibitor supplier) {
    try {
      final data = jsonDecode(supplier.fieldCaptureJson);
      return data is Map && data['route_status'] == 'Missed';
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleMissed(Exhibitor supplier) async {
    final data = <String, dynamic>{};
    try {
      final decoded = jsonDecode(supplier.fieldCaptureJson);
      if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Preserve the working route even if a legacy payload is malformed.
    }
    data['route_status'] = _isMissed(supplier) ? 'Planned' : 'Missed';
    await _db.update(
        'exhibitors', supplier.id!, {'field_capture_json': jsonEncode(data)});
    if (mounted) setState(() => _suppliers = _db.getExhibitors(_tripId));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hall route')),
        body: FutureBuilder<List<Trip>>(
          future: _trips,
          builder: (context, tripSnapshot) {
            final trips = tripSnapshot.data ?? const <Trip>[];
            return FutureBuilder<List<Exhibitor>>(
              future: _suppliers,
              builder: (context, supplierSnapshot) {
                final suppliers = supplierSnapshot.data ?? const <Exhibitor>[];
                final grouped = <String, List<Exhibitor>>{};
                for (final supplier
                    in suppliers.where((item) => item.hall.trim().isNotEmpty)) {
                  grouped
                      .putIfAbsent(supplier.hall.trim(), () => [])
                      .add(supplier);
                }
                final halls = grouped.keys.toList()
                  ..sort((a, b) => a.compareTo(b));
                for (final hall in halls) {
                  grouped[hall]!.sort((a, b) {
                    final weight = _routeWeight(a).compareTo(_routeWeight(b));
                    return weight != 0 ? weight : a.booth.compareTo(b.booth);
                  });
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Your fair route',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                        'Plan where to walk. Use Dashboard Today for your time-based agenda, tasks, and due follow-ups.'),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: _tripId,
                      decoration: const InputDecoration(labelText: 'Trip'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('All trips')),
                        ...trips.map((trip) => DropdownMenuItem<int?>(
                            value: trip.id, child: Text(trip.name))),
                      ],
                      onChanged: _selectTrip,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _importMap,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(_mapPath == null
                          ? 'Import official hall map'
                          : 'Replace hall map'),
                    ),
                    if (_mapPath != null && File(_mapPath!).existsSync()) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_mapPath!),
                            height: 190, fit: BoxFit.cover),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (halls.isEmpty)
                      const EmptyState(
                        icon: Icons.route_outlined,
                        title: 'Add hall and booth details first',
                        message:
                            'Captured suppliers with a hall are grouped here into a practical walking route.',
                      )
                    else
                      ...halls.map((hall) => SectionPanel(
                            title:
                                'Stop ${halls.indexOf(hall) + 1}: Hall $hall',
                            subtitle:
                                '${grouped[hall]!.length} supplier${grouped[hall]!.length == 1 ? '' : 's'}',
                            child: Column(
                              children:
                                  grouped[hall]!.asMap().entries.map((entry) {
                                final supplier = entry.value;
                                final missed = _isMissed(supplier);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                      child: Text('${entry.key + 1}')),
                                  title: Text(supplier.name),
                                  subtitle: Text(
                                      'Booth ${supplier.booth.isEmpty ? 'not recorded' : supplier.booth}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (supplier.shortlisted ||
                                          supplier.rating >= 4)
                                        const Icon(Icons.priority_high,
                                            color: AppColors.amber),
                                      IconButton(
                                        tooltip: missed
                                            ? 'Restore planned booth'
                                            : 'Mark missed booth',
                                        icon: Icon(
                                            missed
                                                ? Icons.undo
                                                : Icons.flag_outlined,
                                            color: missed
                                                ? AppColors.teal
                                                : AppColors.muted),
                                        onPressed: () =>
                                            _toggleMissed(supplier),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          )),
                  ],
                );
              },
            );
          },
        ),
      );
}
