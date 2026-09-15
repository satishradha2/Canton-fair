import 'package:flutter/material.dart';
import '../data/field_work_repository.dart';
import 'field_product_capture_screen.dart';
import 'visit_recording_screen.dart';
import 'visit_history_screen.dart';
import 'ocr_screen.dart';
import 'scanner_screen.dart';
import 'supplier_profile_screen.dart';
import '../data/business_card_capture.dart';
import '../data/contact_qr_parser.dart';
import '../data/team_workspace_service.dart';

class FieldWorkScreen extends StatefulWidget {
  const FieldWorkScreen({super.key});
  @override
  State<FieldWorkScreen> createState() => _FieldWorkScreenState();
}

class _FieldWorkScreenState extends State<FieldWorkScreen> {
  final _repository = FieldWorkRepository();
  late Future<FieldWorkSnapshot> _data = _repository.load(null);
  int? _trip;
  String? _hall;
  bool _selectedOnly = true;
  bool _busy = false;
  String? _error;

  Future<void> _contact(FieldWorkSnapshot data, Map<String, Object?> booth) async {
    final mode = await showModalBottomSheet<String>(context: context,
      showDragHandle: true, builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(
            'Add contact to ${booth['name']}', style: Theme.of(ctx).textTheme.titleLarge)),
          for (final option in const [
            ('card', 'Scan business card', Icons.document_scanner_outlined),
            ('qr', 'Scan contact QR', Icons.qr_code_scanner),
            ('manual', 'Enter manually', Icons.edit_outlined),
          ]) ListTile(leading: Icon(option.$3), title: Text(option.$2),
            onTap: () => Navigator.pop(ctx, option.$1)),
        ],
      )));
    if (mode == null || !mounted) return;
    BusinessCardCapture? card;
    var fields = <String, String>{};
    if (mode == 'card') {
      card = await Navigator.of(context).push<BusinessCardCapture>(MaterialPageRoute(
        builder: (_) => OcrScreen(supplierId: booth['exhibitor_id'] as int,
          supplierName: booth['name'] as String)));
      if (card == null || !mounted) return;
      final company = card.fields['name']?.trim() ?? '';
      if (company.isNotEmpty && company.toLowerCase() !=
          (booth['name'] as String).trim().toLowerCase()) {
        final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Card company differs'),
          content: Text('The card names "$company". Attach this contact and card to "${booth['name']}"? The supplier name will not change.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use selected exhibitor'))]));
        if (confirm != true || !mounted) return;
      }
    } else if (mode == 'qr') {
      final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => const ScannerScreen()));
      if (raw == null || !mounted) return;
      fields = ContactQrParser.parse(raw);
    }
    if (await TeamWorkspaceService().scopeKey() != data.scope) {
      throw StateError('Workspace changed. Reopen field visits.');
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierProfileScreen(
      supplierId: booth['exhibitor_id'] as int, createContact: true,
      contactOnly: true, expectedScope: data.scope, card: card,
      initialContactFields: fields)));
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (mounted) {
        setState(() { _data = _repository.load(_trip); });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseCategory(FieldWorkSnapshot data,
      Map<String, Object?> product) async {
    final categories = await _repository.categories(data.scope);
    if (!mounted) return;
    final input = TextEditingController(text: product['category'] as String? ?? '');
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Category for ${product['name']}'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: input, maxLength: 100,
            decoration: const InputDecoration(labelText: 'Category name',
              helperText: 'Choose below or enter a new category')),
          const SizedBox(height: 16),
          for (final category in categories) ListTile(
            title: Text(category['name'] as String),
            onTap: () => Navigator.pop(ctx, category['name'] as String)),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, input.text),
          child: const Text('Save category')),
      ],
    ));
    // The dialog route can still reference its controller during exit animation.
    if (name == null || !mounted) return;
    await _repository.categorize(data.scope, product['id'] as int, name);
  }

  Future<void> _products(FieldWorkSnapshot data, Map<String, Object?> booth) async {
    final products = await _repository.products(data.scope, booth['exhibitor_id'] as int);
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, Object?>>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .65,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('${booth['name']} products', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('Select a product to assign its category. Add new products using the existing supplier capture screen.'),
          const SizedBox(height: 16),
          if (products.isEmpty) const Text('No products captured for this supplier yet.'),
          for (final product in products) ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(product['name'] as String),
            subtitle: Text(product['category'] as String? ?? 'Needs classification'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(ctx, product)),
        ]),
      )),
    );
    if (selected != null && mounted) await _chooseCategory(data, selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field visits'), actions: [
      IconButton(tooltip: 'Refresh', onPressed: _busy ? null : () =>
        setState(() { _data = _repository.load(_trip); }), icon: const Icon(Icons.refresh)),
    ]),
    body: FutureBuilder<FieldWorkSnapshot>(future: _data, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Padding(
          padding: const EdgeInsets.all(24), child: Text('Could not load field visits. ${snapshot.error}')));
      }
      final data = snapshot.data!;
      final halls = data.booths.map((b) => b['hall'] as String).toSet().toList()..sort();
      final hall = halls.contains(_hall) ? _hall : null;
      final booths = data.booths.where((b) => hall != null && b['hall'] == hall &&
        (!_selectedOnly || b['selected'] == 1 || b['active_visit'] != null)).toList();
      final next = booths.where((b) => b['visited'] == 0 && b['active_visit'] == null).firstOrNull;
      return AbsorbPointer(absorbing: _busy, child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(liveRegion: true, child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          Text('Your next booth visit', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Choose a trip and hall. Select the exhibitors you want to visit, then work through your list.'),
          const SizedBox(height: 24),
          if (data.trips.isEmpty) const Text('Create a trip in Suppliers first.'),
          if (data.trips.isNotEmpty) DropdownButtonFormField<int>(
            key: ValueKey('trip-${data.tripId}'), initialValue: data.tripId,
            isExpanded: true, decoration: const InputDecoration(labelText: 'Trip'),
            items: [for (final trip in data.trips) DropdownMenuItem(
              value: trip['id'] as int, child: Text(trip['name'] as String))],
            onChanged: (value) => setState(() {
              _trip = value; _hall = null; _data = _repository.load(value);
            })),
          const SizedBox(height: 16),
          if (data.tripId != null) OutlinedButton.icon(
            icon: const Icon(Icons.playlist_add), label: const Text('Include trip suppliers'),
            onPressed: () => _act(() => _repository.includeTripSuppliers(data.scope, data.tripId!))),
          if (data.tripId != null) TextButton.icon(
            icon: const Icon(Icons.history), label: const Text('Visit history and recordings'),
            onPressed: () => _act(() async {
              await Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => VisitHistoryScreen(scope: data.scope, tripId: data.tripId!)));
            })),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(key: ValueKey('hall-${data.tripId}-$hall'),
            initialValue: hall, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Which hall are you visiting?'),
            items: [for (final item in halls) DropdownMenuItem(value: item,
              child: Text(item.isEmpty ? 'Hall not recorded' : 'Hall $item'))],
            onChanged: (value) => setState(() => _hall = value)),
          const SizedBox(height: 16),
          SwitchListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Only exhibitors selected to visit'),
            value: _selectedOnly, onChanged: (value) => setState(() => _selectedOnly = value)),
          const Text('Visit selection is separate from supplier ratings and product shortlists.'),
          const SizedBox(height: 20),
          if (hall == null) const Text('Select a hall to see its exhibitors.'),
          if (hall != null && booths.isEmpty) const Text('No matching exhibitors. Turn off the filter to select booths in this hall.'),
          for (final booth in booths) Card(child: Padding(
            padding: const EdgeInsets.all(18), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (next?['id'] == booth['id']) const Padding(
                  padding: EdgeInsets.only(bottom: 8), child: Text('SUGGESTED NEXT')),
                Text(booth['name'] as String, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('Booth ${booth['booth']}  |  ${booth['visited'] == 1 ? 'Visited' : 'Not visited'}'),
                CheckboxListTile(contentPadding: EdgeInsets.zero,
                  title: const Text('Want to visit'), value: booth['selected'] == 1,
                  onChanged: (value) => _act(() => _repository.selectBooth(
                    data.scope, booth['id'] as int, value ?? false))),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  if (booth['active_visit'] != null) OutlinedButton.icon(
                    icon: const Icon(Icons.mic_none), label: const Text('Record conversation / note'),
                    onPressed: () => _act(() async {
                      await Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => VisitRecordingScreen(scope: data.scope,
                          visitId: booth['active_visit'] as int,
                          supplierName: booth['name'] as String)));
                    })),
                  OutlinedButton.icon(icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add contact'),
                    onPressed: () => _act(() => _contact(data, booth))),
                  OutlinedButton.icon(icon: const Icon(Icons.add),
                    label: const Text('Add product'), onPressed: () => _act(() async {
                      await Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => FieldProductCaptureScreen(scope: data.scope,
                          supplierId: booth['exhibitor_id'] as int,
                          supplierName: booth['name'] as String)));
                    })),
                  FilledButton(onPressed: () => _act(() => booth['active_visit'] == null
                    ? _repository.startVisit(data.scope, booth['id'] as int)
                    : _repository.finishVisit(data.scope, booth['active_visit'] as int)),
                    child: Text(booth['active_visit'] == null ? 'Start visit' : 'Finish visit')),
                  OutlinedButton(onPressed: () => _act(() => _products(data, booth)),
                    child: const Text('Product categories')),
                ]),
              ],
            ),
          )),
          const SizedBox(height: 20),
          const Text('Initial field-work preview. Team edits currently require an online permission check. Field records sync only after server migration 018 is installed. Booth ordering is not indoor navigation.'),
        ],
      ));
    }),
  );
}
