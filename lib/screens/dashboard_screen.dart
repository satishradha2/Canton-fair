import 'package:flutter/material.dart';
import '../data/database.dart';
import '../models/models.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final db = TradeDatabase.instance;
  late Future<List<Map<String, dynamic>>> _futureStats;
  late Future<List<Map<String, dynamic>>> _futureCloseouts;
  late Future<List<Product>> _futureTopShortlist;

  @override
  void initState() {
    super.initState();
    _futureStats = db.getStats();
    _futureCloseouts = db.getTripCloseoutSummaries();
    _futureTopShortlist = _loadTopShortlist();
  }

  void _reload() => setState(() {
        _futureStats = db.getStats();
        _futureCloseouts = db.getTripCloseoutSummaries();
        _futureTopShortlist = _loadTopShortlist();
      });

  Future<List<Product>> _loadTopShortlist() async {
    final products = await db.getShortlistedProducts();
    products.sort((a, b) => _shortlistScore(b).compareTo(_shortlistScore(a)));
    return products.take(20).toList();
  }

  double _shortlistScore(Product p) {
    final ratingScore = (p.rating / 5.0) * 40.0;
    final priceScore = p.quotedPrice == null ? 0.0 : 1000.0 / (1.0 + p.quotedPrice!.abs());
    final moqScore = p.moq == null ? 0.0 : 30.0 / (1.0 + p.moq!);
    final leadMatch = RegExp(r'\d+').firstMatch(p.leadTime);
    final lead = leadMatch == null ? null : double.tryParse(leadMatch.group(0)!);
    final leadScore = lead == null ? 0.0 : 15.0 / (1.0 + lead);
    return ratingScore + priceScore + moqScore + leadScore;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureStats,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!;
          final colorPalette = [
            Colors.indigo,
            Colors.teal,
            Colors.orange,
            Colors.purple,
            Colors.green,
          ];
          final icons = [Icons.public, Icons.business, Icons.inventory_2, Icons.star, Icons.alarm];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Canton Fair Operations',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Trip intelligence dashboard for supplier discovery, follow-ups, and shortlisting.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stats.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.55,
                ),
                itemBuilder: (context, i) {
                  return StatCard(
                    label: stats[i]['label'].toString(),
                    value: (stats[i]['value'] as int),
                    icon: icons[i % icons.length],
                    color: colorPalette[i % colorPalette.length],
                  );
                },
              ),
              const SizedBox(height: 14),
              const Card(
                child: ListTile(
                  title: Text('Feature completeness status'),
                  subtitle: Text(
                    'Scanners, OCR, file attachments, and cloud sync are integrated as dedicated feature modules in next step for production hardening.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Trip closeout status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _futureCloseouts,
                builder: (context, closeSnap) {
                  if (!closeSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (closeSnap.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No trip data available yet. Add at least one trip first.'),
                    );
                  }
                  return Column(
                    children: closeSnap.data!.map((trip) {
                      final isClosed = (trip['closed_at'] as String).isNotEmpty;
                      return Card(
                        child: ListTile(
                          title: Text(trip['trip_name']?.toString() ?? 'Trip'),
                          subtitle: Text(
                            'Suppliers: ${trip['exhibitor_count']} | Products: ${trip['product_count']} | '
                            'Contacts: ${trip['contact_count']} | Meetings: ${trip['meeting_count']} | '
                            'Shortlists: E${trip['shortlisted_exhibitor_count']} / P${trip['shortlisted_product_count']}',
                          ),
                          trailing: isClosed ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.hourglass_empty),
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text('Top shortlisted products (recommendation score)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              FutureBuilder<List<Product>>(
                future: _futureTopShortlist,
                builder: (context, scoreSnap) {
                  if (!scoreSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (scoreSnap.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No shortlisted products yet.'),
                    );
                  }
                  return Column(
                    children: scoreSnap.data!.map((p) {
                      return Card(
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            'Supplier ID: ${p.exhibitorId} | ${p.quotedPrice == null ? "No price" : "${p.quotedPrice} ${p.priceCurrency}"} | MOQ: ${p.moq ?? "-"} | Lead: ${p.leadTime}',
                          ),
                          trailing: Text(_shortlistScore(p).toStringAsFixed(2)),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
