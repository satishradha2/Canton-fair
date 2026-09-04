import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import 'quote_approval_screen.dart';

class ProcurementWorkspaceScreen extends StatefulWidget {
  const ProcurementWorkspaceScreen({super.key});

  @override
  State<ProcurementWorkspaceScreen> createState() =>
      _ProcurementWorkspaceScreenState();
}

class _ProcurementWorkspaceScreenState extends State<ProcurementWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  final _db = TradeDatabase.instance;
  late final TabController _tabs;
  late Future<_ProcurementData> _data;
  final _documentSearch = TextEditingController();
  Future<List<Map<String, dynamic>>>? _documents;
  int? _selectedQuoteId;
  final _quantity = TextEditingController(text: '100');
  final _freight = TextEditingController(text: '0');
  final _duty = TextEditingController(text: '0');
  final _otherCosts = TextEditingController(text: '0');
  final _rate = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _data = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _documentSearch.dispose();
    _quantity.dispose();
    _freight.dispose();
    _duty.dispose();
    _otherCosts.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<_ProcurementData> _load() async {
    final suppliers = await _db.getExhibitors(null);
    final products = (await _db.queryAll('products')).map(Product.fromMap).toList();
    final quotes = await _db.getQuotesForApproval();
    final meetings = await _db.getMeetings();
    return _ProcurementData(suppliers, products, quotes, meetings);
  }

  void _refresh() => setState(() => _data = _load());

  Map<String, dynamic> _verification(Exhibitor supplier) {
    try {
      final value = jsonDecode(supplier.verificationJson);
      return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  List<_CertificateAlert> _certificateAlerts(List<Exhibitor> suppliers) {
    final today = DateTime.now();
    final window = today.add(const Duration(days: 60));
    final alerts = <_CertificateAlert>[];
    for (final supplier in suppliers) {
      final certificates = _verification(supplier)['certificates'];
      if (certificates is! List) continue;
      for (final item in certificates.whereType<Map>()) {
        final certificate = Map<String, dynamic>.from(item);
        final expiry = DateTime.tryParse(certificate['expiry'] as String? ?? '');
        if (expiry != null && expiry.isBefore(window)) {
          alerts.add(_CertificateAlert(
            supplier: supplier.name,
            type: certificate['type'] as String? ?? 'Certificate',
            expiry: expiry,
            verified: certificate['verified'] == true,
          ));
        }
      }
    }
    alerts.sort((a, b) => a.expiry.compareTo(b.expiry));
    return alerts;
  }

  Future<void> _saveLandedCost(_ProcurementData data) async {
    final quote = data.quotes.where((item) => item['id'] == _selectedQuoteId).firstOrNull;
    if (quote == null) return;
    final productId = quote['product_id'] as int;
    final product = data.products.where((item) => item.id == productId).firstOrNull;
    if (product == null) return;
    final quantity = double.tryParse(_quantity.text.trim()) ?? 0;
    final unitPrice = (quote['unit_price'] as num?)?.toDouble() ?? 0;
    final freight = double.tryParse(_freight.text.trim()) ?? 0;
    final duty = double.tryParse(_duty.text.trim()) ?? 0;
    final other = double.tryParse(_otherCosts.text.trim()) ?? 0;
    final rate = double.tryParse(_rate.text.trim()) ?? 1;
    final goods = quantity * unitPrice;
    final sourceTotal = goods + freight + other + goods * duty / 100;
    final details = <String, dynamic>{};
    try {
      final decoded = jsonDecode(product.detailsJson);
      if (decoded is Map) details.addAll(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    details['landed_cost'] = {
      'quote_id': quote['id'],
      'quantity': quantity,
      'freight': freight,
      'duty_percent': duty,
      'other_costs': other,
      'source_currency': quote['currency'] ?? product.priceCurrency,
      'usd_rate': rate,
      'source_total': sourceTotal,
      'usd_total': sourceTotal * rate,
      'usd_unit_cost': quantity == 0 ? 0 : sourceTotal * rate / quantity,
      'saved_at': DateTime.now().toIso8601String(),
    };
    await _db.update('products', productId, {'details_json': jsonEncode(details)});
    await _db.logAudit('Saved landed cost', '${product.name} | quote ${quote['id']}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Landed cost saved to the product decision record.')),
    );
  }

  Future<void> _importCsv() async {
    final trips = await _db.getTrips();
    if (trips.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a trip before importing suppliers.')),
        );
      }
      return;
    }
    const channel = MethodChannel('canton_fair_crm/backup');
    final sourcePath = await channel.invokeMethod<String>('pickDocument');
    if (sourcePath == null) return;
    try {
      final source = await File(sourcePath).readAsString();
      final rows = const CsvToListConverter(shouldParseNumbers: false).convert(source);
      if (rows.length < 2) throw const FormatException('The spreadsheet has no supplier rows.');
      final headers = rows.first
          .map((item) => item.toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .toList();
      final nameIndex = _column(headers, ['supplier', 'suppliername', 'company', 'companyname', 'name']);
      if (nameIndex == null) {
        throw const FormatException('Add a Supplier or Company column to the CSV.');
      }
      if (!mounted) return;
      final trip = await showDialog<Trip>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Import suppliers into trip'),
          children: trips.map((item) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, item),
            child: Text(item.name),
          )).toList(),
        ),
      );
      if (trip == null) return;
      var added = 0;
      for (final row in rows.skip(1)) {
        final name = _value(row, nameIndex).trim();
        if (name.isEmpty) continue;
        await _db.insert('exhibitors', {
          'trip_id': trip.id,
          'name': name,
          'booth': _value(row, _column(headers, ['booth', 'stand'])),
          'hall': _value(row, _column(headers, ['hall'])),
          'category': _value(row, _column(headers, ['category', 'productcategory'])),
          'country': _value(row, _column(headers, ['country'])),
          'notes': _value(row, _column(headers, ['notes', 'note'])),
          'rating': int.tryParse(_value(row, _column(headers, ['rating']))) ?? 0,
        });
        added++;
      }
      await _db.logAudit('Imported suppliers', '$added supplier rows into ${trip.name}');
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $added suppliers into ${trip.name}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import CSV: $error')),
        );
      }
    }
  }

  int? _column(List<String> headers, List<String> choices) {
    for (final choice in choices) {
      final index = headers.indexOf(choice);
      if (index >= 0) return index;
    }
    return null;
  }

  String _value(List<dynamic> row, int? index) =>
      index == null || index >= row.length ? '' : row[index].toString();

  Future<void> _searchDocuments() async {
    setState(() => _documents = _db.searchAttachments(_documentSearch.text));
  }

  Future<void> _shareManagementReport(_ProcurementData data) async {
    final alerts = _certificateAlerts(data.suppliers);
    final now = DateTime.now();
    final approved = data.quotes.where((item) => item['approval_status'] == 'Approved').length;
    final pending = data.quotes.where((item) => item['approval_status'] == 'Pending approval').length;
    final openTasks = data.meetings.where((item) => !item.completed).length;
    final text = '''Canton Fair Management Report
Generated: ${now.toLocal().toString().substring(0, 16)}

Suppliers captured: ${data.suppliers.length}
Shortlisted suppliers: ${data.suppliers.where((item) => item.shortlisted).length}
Products captured: ${data.products.length}
Official quote revisions: ${data.quotes.length}
Approved quotes: $approved
Quotes pending approval: $pending
Open follow-ups: $openTasks
Certificate expiry alerts: ${alerts.length}

Priority certificate actions:
${alerts.take(5).map((item) => '- ${item.supplier}: ${item.type} expires ${_date(item.expiry)}').join('\n').ifEmpty('- None')}
''';
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Canton Fair management report'));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Procurement workspace'),
          actions: [
            IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Decisions'),
              Tab(text: 'Costing'),
              Tab(text: 'Data'),
              Tab(text: 'Alerts & report'),
            ],
          ),
        ),
        body: FutureBuilder<_ProcurementData>(
          future: _data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!;
            return TabBarView(
              controller: _tabs,
              children: [
                _decisions(data),
                _costing(data),
                _dataTools(),
                _alertsAndReport(data),
              ],
            );
          },
        ),
      );

  Widget _decisions(_ProcurementData data) {
    final performance = data.suppliers.map((supplier) {
      final related = data.meetings.where((item) => item.exhibitorId == supplier.id).toList();
      final completed = related.where((item) => item.completed).length;
      final score = supplier.decisionScore.round();
      return (supplier: supplier, completed: completed, total: related.length, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionPanel(
        title: 'Approval workflow',
        subtitle: 'Quote approval is role-governed by the cloud team: viewers read, members work, admins manage membership.',
        child: FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuoteApprovalScreen())).then((_) => _refresh()),
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('Review quote approvals'),
        ),
      ),
      const SizedBox(height: 16),
      SectionPanel(
        title: 'Supplier performance',
        subtitle: 'Decision score combines quality, response speed, trust, MOQ fit, and reliability. Follow-up completion adds the field delivery signal.',
        child: performance.isEmpty
            ? const Text('Capture suppliers to see performance.')
            : Column(children: performance.take(12).map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(item.score.toString())),
              title: Text(item.supplier.name),
              subtitle: Text('Score ${item.score}/100 | ${item.completed}/${item.total} follow-ups completed'),
              trailing: InfoChip(label: item.supplier.decision, color: item.supplier.shortlisted ? AppColors.teal : AppColors.muted),
            )).toList()),
      ),
      const SizedBox(height: 16),
      SectionPanel(
        title: 'Quote revision history',
        subtitle: 'Every new quote is kept as a version. The most recent version is the current commercial offer; the full history remains available on the product.',
        child: data.quotes.isEmpty
            ? const Text('No quote versions recorded.')
            : Column(children: data.quotes.take(10).map((quote) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_outlined),
              title: Text('${quote['supplier_name'] ?? 'Supplier'} - ${quote['product_name'] ?? 'Product'}'),
              subtitle: Text('Revision ${quote['revision_number']} of ${quote['revision_count']} | ${quote['unit_price'] ?? '-'} ${quote['currency'] ?? 'USD'} | ${quote['approval_status'] ?? 'Draft'}'),
            )).toList()),
      ),
    ]);
  }

  Widget _costing(_ProcurementData data) {
    final quotes = data.quotes.where((item) => item['unit_price'] != null).toList();
    final selected = quotes.where((item) => item['id'] == _selectedQuoteId).firstOrNull;
    final unitPrice = (selected?['unit_price'] as num?)?.toDouble() ?? 0;
    final quantity = double.tryParse(_quantity.text) ?? 0;
    final freight = double.tryParse(_freight.text) ?? 0;
    final duty = double.tryParse(_duty.text) ?? 0;
    final other = double.tryParse(_otherCosts.text) ?? 0;
    final rate = double.tryParse(_rate.text) ?? 1;
    final goods = unitPrice * quantity;
    final total = goods + freight + other + goods * duty / 100;
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionPanel(
        title: 'Landed-cost calculator',
        subtitle: 'Select an official quote, then calculate the buying decision with freight, duty, other costs, and your USD exchange rate.',
        child: Column(children: [
          DropdownButtonFormField<int>(
            initialValue: quotes.any((item) => item['id'] == _selectedQuoteId) ? _selectedQuoteId : null,
            decoration: const InputDecoration(labelText: 'Quote revision'),
            items: quotes.map((quote) => DropdownMenuItem<int>(
              value: quote['id'] as int,
              child: Text('${quote['supplier_name']} - ${quote['product_name']} | ${quote['unit_price']} ${quote['currency']}'),
            )).toList(),
            onChanged: (value) => setState(() => _selectedQuoteId = value),
          ),
          const SizedBox(height: 10),
          TextField(controller: _quantity, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Order quantity')),
          TextField(controller: _freight, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Freight in quote currency')),
          TextField(controller: _duty, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Duty percent')),
          TextField(controller: _otherCosts, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Other landed costs in quote currency')),
          TextField(controller: _rate, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'USD per ${selected?['currency'] ?? 'source currency'}')),
          const SizedBox(height: 16),
          Text('Goods: ${goods.toStringAsFixed(2)} ${selected?['currency'] ?? ''}'),
          Text('Landed total: ${total.toStringAsFixed(2)} ${selected?['currency'] ?? ''}'),
          Text('USD total: ${(total * rate).toStringAsFixed(2)} | USD unit cost: ${quantity == 0 ? '0.00' : (total * rate / quantity).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: selected == null ? null : () => _saveLandedCost(data), icon: const Icon(Icons.save_outlined), label: const Text('Save to product decision')),
        ]),
      ),
    ]);
  }

  Widget _dataTools() => ListView(padding: const EdgeInsets.all(16), children: [
    SectionPanel(
      title: 'Import supplier spreadsheet',
      subtitle: 'Import a CSV with Supplier or Company, Booth, Hall, Category, Country, Notes, and Rating columns. You choose the destination trip before saving.',
      child: FilledButton.icon(onPressed: _importCsv, icon: const Icon(Icons.upload_file_outlined), label: const Text('Import CSV suppliers')),
    ),
    const SizedBox(height: 16),
    SectionPanel(
      title: 'Search supplier files',
      subtitle: 'Find saved photos, PDFs, catalogues, and evidence by their note, type, or filename.',
      child: Column(children: [
        TextField(controller: _documentSearch, onSubmitted: (_) => _searchDocuments(), decoration: InputDecoration(labelText: 'Search documents', suffixIcon: IconButton(onPressed: _searchDocuments, icon: const Icon(Icons.search)))),
        if (_documents != null) FutureBuilder<List<Map<String, dynamic>>>(
          future: _documents,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
            if (snapshot.data!.isEmpty) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('No matching files.'));
            return Column(children: snapshot.data!.map((file) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(file['kind'] == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.attach_file_outlined),
              title: Text(file['note'] as String? ?? 'Untitled file'),
              subtitle: Text('${file['supplier_name']}${file['product_name'] == null ? '' : ' | ${file['product_name']}'}'),
            )).toList());
          },
        ),
      ]),
    ),
  ]);

  Widget _alertsAndReport(_ProcurementData data) {
    final alerts = _certificateAlerts(data.suppliers);
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionPanel(
        title: 'Document expiry alerts',
        subtitle: 'Certificates expiring within 60 days, or already expired. Edit the certificate register from the supplier Verification tab.',
        child: alerts.isEmpty
            ? const Text('No certificate expiry alerts.')
            : Column(children: alerts.map((item) {
              final expired = item.expiry.isBefore(DateTime.now());
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(expired ? Icons.warning_amber_outlined : Icons.event_outlined, color: expired ? AppColors.danger : AppColors.amber),
                title: Text('${item.supplier} - ${item.type}'),
                subtitle: Text('${expired ? 'Expired' : 'Expires'} ${_date(item.expiry)} | ${item.verified ? 'Verified' : 'Not verified'}'),
              );
            }).toList()),
      ),
      const SizedBox(height: 16),
      SectionPanel(
        title: 'Post-fair management report',
        subtitle: 'Share a compact leadership report with supplier pipeline, commercial approvals, task load, and certificate exposure.',
        child: FilledButton.icon(onPressed: () => _shareManagementReport(data), icon: const Icon(Icons.ios_share_outlined), label: const Text('Share management report')),
      ),
    ]);
  }
}

class _ProcurementData {
  final List<Exhibitor> suppliers;
  final List<Product> products;
  final List<Map<String, dynamic>> quotes;
  final List<Meeting> meetings;
  const _ProcurementData(this.suppliers, this.products, this.quotes, this.meetings);
}

class _CertificateAlert {
  final String supplier;
  final String type;
  final DateTime expiry;
  final bool verified;
  const _CertificateAlert({required this.supplier, required this.type, required this.expiry, required this.verified});
}

extension _IterableLookup<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension _StringFallback on String {
  String ifEmpty(String value) => isEmpty ? value : this;
}
