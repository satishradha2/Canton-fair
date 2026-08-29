import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/database.dart';
import '../models/models.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final db = TradeDatabase.instance;

  Future<String> _writeCsv(List<List<dynamic>> rows, String filename) async {
    final docs = await getExternalStorageDirectory();
    final file = File('${docs!.path}/$filename');
    final csvData = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csvData, encoding: utf8);
    return file.path;
  }

  Future<void> _exportAllExhibitors() async {
    final rows = <List<dynamic>>[
      [
        'Trip ID',
        'Supplier',
        'Booth',
        'Hall',
        'Category',
        'Country',
        'Shortlisted',
        'Rating',
      ]
    ];
    final exhibitors = await db.queryAll('exhibitors');
    for (final e in exhibitors) {
      rows.add([
        e['trip_id'],
        e['name'],
        e['booth'],
        e['hall'],
        e['category'],
        e['country'],
        e['shortlisted'],
        e['rating'],
      ]);
    }
    final path = await _writeCsv(rows, 'canton_fair_exhibitors.csv');
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _exportShortlist() async {
    final rows = <List<dynamic>>[
      ['Supplier / Product', 'Type', 'RefID', 'Price', 'Currency', 'MoQ', 'LeadTime', 'Shortlisted', 'Score'],
    ];
    final ex = await db.queryAll('exhibitors', where: 'shortlisted = 1');
    for (final e in ex) {
      rows.add([
        e['name'],
        'Supplier',
        e['id'],
        '',
        '',
        '',
        '',
        '1',
        '-',
      ]);
    }
    final products = await db.getShortlistedProducts()..sort(
      (a, b) => _shortlistScore(b).compareTo(_shortlistScore(a)),
    );
    for (final p in products) {
      rows.add([
        p.name,
        'Product',
        p.id,
        p.quotedPrice ?? '',
        p.priceCurrency,
        p.moq ?? '',
        p.leadTime,
        '1',
        _shortlistScore(p).toStringAsFixed(2),
      ]);
    }
    final path = await _writeCsv(rows, 'canton_fair_shortlist.csv');
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _exportTripRankedShortlist() async {
    final rows = <List<dynamic>>[
      [
        'Trip',
        'Trip ID',
        'Product',
        'Product ID',
        'Exhibitor',
        'Exhibitor ID',
        'Price',
        'Currency',
        'MOQ',
        'LeadTime',
        'Rating',
        'Score',
        'Rank in Trip',
      ],
    ];

    final raw = await db.getShortlistedProductsWithTrip();
    final byTrip = <int?, List<Map<String, dynamic>>>{};
    for (final r in raw) {
      final tripId = r['trip_id'] as int?;
      byTrip.putIfAbsent(tripId, () => <Map<String, dynamic>>[]).add(r);
    }

    for (final entry in byTrip.entries) {
      final products = entry.value.map((r) {
        final p = Product(
          id: r['id'] as int?,
          exhibitorId: r['exhibitor_id'] as int,
          name: r['name'] as String,
          modelCode: r['model_code'] as String? ?? '',
          specs: r['specs'] as String? ?? '',
          moq: r['moq'] != null ? (r['moq'] as num).toDouble() : null,
          quotedPrice: r['quoted_price'] != null ? (r['quoted_price'] as num).toDouble() : null,
          priceCurrency: r['price_currency'] as String? ?? 'USD',
          leadTime: r['lead_time'] as String? ?? '',
          paymentTerms: r['payment_terms'] as String? ?? '',
          shortlisted: true,
          rating: r['rating'] as int? ?? 0,
        );
        final score = _shortlistScore(p);
        return {'score': score, 'product': r, 'model': p};
      }).toList()
        ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      for (int i = 0; i < products.length; i++) {
        final row = products[i];
        final score = row['score'] as double;
        final data = row['product'] as Map<String, dynamic>;
        final tripName = data['trip_name']?.toString() ?? 'Unknown trip';
        final tripId = data['trip_id'];
        rows.add([
          tripName,
          tripId ?? '',
          data['name'],
          data['id'],
          data['exhibitor_name'],
          data['exhibitor_id'],
          data['quoted_price'] ?? '',
          data['price_currency'],
          data['moq'] ?? '',
          data['lead_time'],
          data['rating'],
          score.toStringAsFixed(2),
          i + 1,
        ]);
      }
    }
    final path = await _writeCsv(rows, 'canton_fair_trip_ranked_shortlist.csv');
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _exportTripRankedShortlistPdf() async {
    final doc = pw.Document();
    final now = DateTime.now().toLocal().toIso8601String();
    final raw = await db.getShortlistedProductsWithTrip();
    final byTrip = <int?, List<Map<String, dynamic>>>{};
    for (final r in raw) {
      final tripId = r['trip_id'] as int?;
      byTrip.putIfAbsent(tripId, () => <Map<String, dynamic>>[]).add(r);
    }
    final tripEntries = byTrip.entries.toList()
      ..sort(
        (a, b) => ((a.value.first['trip_name']?.toString() ?? '')).compareTo(
          b.value.first['trip_name']?.toString() ?? '',
        ),
      );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          final children = <pw.Widget>[
            pw.Text(
              'Canton Fair Trip Ranked Shortlist Report',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Generated: $now'),
            pw.SizedBox(height: 12),
            pw.Text('Total shortlisted products: ${raw.length}'),
            pw.SizedBox(height: 16),
          ];

          if (tripEntries.isEmpty) {
            children.add(pw.Text('No shortlisted products found.'));
            return children;
          }

          for (final entry in tripEntries) {
            final tripProducts = entry.value
                .map((r) {
                  final p = Product(
                    id: r['id'] as int?,
                    exhibitorId: r['exhibitor_id'] as int,
                    name: r['name'] as String,
                    modelCode: r['model_code'] as String? ?? '',
                    specs: r['specs'] as String? ?? '',
                    moq: r['moq'] != null ? (r['moq'] as num).toDouble() : null,
                    quotedPrice: r['quoted_price'] != null ? (r['quoted_price'] as num).toDouble() : null,
                    priceCurrency: r['price_currency'] as String? ?? 'USD',
                    leadTime: r['lead_time'] as String? ?? '',
                    paymentTerms: r['payment_terms'] as String? ?? '',
                    shortlisted: true,
                    rating: r['rating'] as int? ?? 0,
                  );
                  return {
                    'product': r,
                    'score': _shortlistScore(p),
                  };
                })
                .toList()
              ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

            final tripName = entry.value.first['trip_name']?.toString() ?? 'Unknown trip';
            final tripId = entry.key;
            final tripStart = entry.value.first['trip_start_date']?.toString();
            final tripEnd = entry.value.first['trip_end_date']?.toString();

            children.add(
              pw.Text(
                'Trip: $tripName  (Trip ID: ${tripId ?? "—"})',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            );
            if (tripStart != null || tripEnd != null) {
              children.add(pw.Text('Dates: ${tripStart ?? "—"} to ${tripEnd ?? "—"}'));
            }
            children.add(pw.SizedBox(height: 8));

            final rows = tripProducts
                .asMap()
                .entries
                .map((entryRow) {
                  final data = entryRow.value['product'] as Map<String, dynamic>;
                  final score = entryRow.value['score'] as double;
                  return [
                    '${entryRow.key + 1}',
                    data['name']?.toString() ?? '',
                    data['exhibitor_name']?.toString() ?? '',
                    data['quoted_price']?.toString() ?? '',
                    data['price_currency']?.toString() ?? '',
                    data['moq']?.toString() ?? '',
                    data['lead_time']?.toString() ?? '',
                    data['rating']?.toString() ?? '',
                    score.toStringAsFixed(2),
                  ];
                })
                .toList()
                .cast<List<String>>();

            children.add(
              pw.Table.fromTextArray(
                headers: const [
                  'Rank',
                  'Product',
                  'Exhibitor',
                  'Price',
                  'Currency',
                  'MOQ',
                  'LeadTime',
                  'Rating',
                  'Score',
                ],
                data: rows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: const {
                  0: pw.Alignment.centerRight,
                  8: pw.Alignment.centerRight,
                },
              ),
            );
            children.add(pw.SizedBox(height: 16));
          }

          return children;
        },
      ),
    );

    final docDir = await getTemporaryDirectory();
    final file = File('${docDir.path}/canton_fair_trip_ranked_shortlist_report.pdf');
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
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

  Future<void> _exportFollowUps() async {
    final rows = <List<dynamic>>[
      ['Exhibitor ID', 'Meeting Date', 'Follow Up Date', 'Outcome', 'Priority', 'Notes']
    ];
    final meetings = await db.getDueFollowUps();
    for (final m in meetings) {
      rows.add([
        m.exhibitorId,
        m.meetingDate.toIso8601String(),
        m.followUpDate?.toIso8601String() ?? '',
        m.outcome,
        m.priority,
        m.notes,
      ]);
    }
    final path = await _writeCsv(rows, 'canton_fair_followups.csv');
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> _exportShortlistReportPdf() async {
    final doc = pw.Document();
    final ex = await db.queryAll('exhibitors', where: 'shortlisted = 1', orderBy: 'name ASC');
    final products = await db.getShortlistedProducts();
    final followUps = await db.getDueFollowUps();
    final now = DateTime.now().toLocal().toIso8601String();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Canton Fair Shortlist Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Generated: $now'),
              pw.SizedBox(height: 12),
              pw.Text('Shortlisted suppliers: ${ex.length}'),
              pw.Text('Shortlisted products: ${products.length}'),
              pw.SizedBox(height: 12),
              pw.Text('Suppliers'),
              ...ex.map((e) => pw.Text('${e['name']} | Booth ${e['booth']} | Rating ${e['rating']}')),
              pw.SizedBox(height: 12),
              pw.Text('Products'),
              ...products.map(
                (p) => pw.Text(
                  '${p.name} | ${p.quotedPrice == null ? "-" : "${p.quotedPrice} ${p.priceCurrency}"} | MOQ: ${p.moq ?? "-"}',
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Active follow-ups: ${followUps.where((f) => f.followUpDate != null).length}'),
            ],
          );
        },
      ),
    );
    final docDir = await getTemporaryDirectory();
    final file = File('${docDir.path}/canton_fair_shortlist_report.pdf');
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _exportTripCloseoutSummary() async {
    final rows = <List<dynamic>>[
      [
        'Trip ID',
        'Trip',
        'Start date',
        'End date',
        'Exhibitors',
        'Products',
        'Contacts',
        'Meetings',
        'Shortlisted suppliers',
        'Shortlisted products',
        'Closed at',
        'Close note',
      ]
    ];
    final rowsRaw = await db.getTripCloseoutSummaries();
    for (final r in rowsRaw) {
      rows.add([
        r['trip_id'],
        r['trip_name'],
        r['start_date'],
        r['end_date'],
        r['exhibitor_count'],
        r['product_count'],
        r['contact_count'],
        r['meeting_count'],
        r['shortlisted_exhibitor_count'],
        r['shortlisted_product_count'],
        r['closed_at'],
        r['close_note'],
      ]);
    }
    final path = await _writeCsv(rows, 'canton_fair_trip_closeout_summary.csv');
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Widget _card(String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.download),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Export & Sharing Hub', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _card('Export all exhibitors', 'Download all captured supplier details in CSV', _exportAllExhibitors),
        _card('Export shortlist', 'Download shortlisted suppliers and products', _exportShortlist),
        _card('Export trip ranked shortlist', 'Rank shortlisted products per trip by score', _exportTripRankedShortlist),
        _card('Export trip ranked shortlist PDF', 'Generate ranked shortlist report grouped by trip', _exportTripRankedShortlistPdf),
        _card('Export follow-ups', 'Export meeting follow-up pipeline', _exportFollowUps),
        _card('Export shortlist PDF', 'Generate and share shortlisted supplier report', _exportShortlistReportPdf),
        _card('Export trip closeout summary', 'Download supplier/contact/product counts and close status per trip', _exportTripCloseoutSummary),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            title: Text('PDF and cloud backup'),
            subtitle: Text('Planned in next release with signed trip report generation and optional upload sync.'),
          ),
        ),
      ],
    );
  }
}
