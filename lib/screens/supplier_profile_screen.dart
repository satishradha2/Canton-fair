import 'package:flutter/material.dart';

import '../data/business_card_capture.dart';
import '../data/database.dart';
import '../data/supplier_profile.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';

class SupplierProfileScreen extends StatefulWidget {
  const SupplierProfileScreen({super.key, required this.supplierId, this.contactId, this.card});
  final int supplierId;
  final int? contactId;
  final BusinessCardCapture? card;
  @override
  State<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends State<SupplierProfileScreen> {
  final _controllers = {for (final key in {...SupplierProfile.companyFields.keys, ...SupplierProfile.contactFields.keys})
    key: TextEditingController()};
  final _baseline = <String, String>{};
  final _selected = <String>{};
  Exhibitor? _supplier;
  List<Contact> _contacts = [];
  Contact? _contact;
  String? _scope;
  String? _error;
  bool _busy = true;
  bool _saveContact = false;

  @override
  void initState() { super.initState(); _load(); }

  void _setFields(Map<String, String> values) {
    for (final entry in values.entries) {
      _baseline[entry.key] = entry.value;
      final incoming = widget.card?.fields[entry.key] ?? '';
      final fill = entry.value.isEmpty && incoming.isNotEmpty;
      if (fill) { _selected.add(entry.key); } else { _selected.remove(entry.key); }
      _controllers[entry.key]!.text = fill ? incoming : entry.value;
    }
  }

  Future<void> _load() async {
    try {
      _scope = await TeamWorkspaceService().scopeKey();
      final supplier = await TradeDatabase.instance.getExhibitorById(widget.supplierId);
      final contacts = await TradeDatabase.instance.getContacts(widget.supplierId);
      if (supplier == null) throw StateError('Supplier no longer exists.');
      if (await TeamWorkspaceService().scopeKey() != _scope) throw StateError('Workspace changed. Please reopen.');
      if (!mounted) return;
      _supplier = supplier;
      _contacts = contacts;
      for (final contact in contacts) {
        if (contact.id == widget.contactId) _contact = contact;
      }
      _saveContact = _contact != null || (widget.card != null &&
          SupplierProfile.contactFields.keys.any((key) => widget.card!.fields[key]?.isNotEmpty ?? false));
      _setFields(SupplierProfile.company(supplier));
      _setFields(SupplierProfile.contact(_contact));
    } catch (error) {
      _error = error is StateError ? error.message.toString() : 'Could not load supplier details. Close and retry.';
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _chooseContact(int? id) async {
    if (SupplierProfile.contactFields.keys.any((key) => _controllers[key]!.text != (_baseline[key] ?? ''))) {
      final change = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Switch the contact being edited?'),
        content: const Text('Unsaved contact edits will be replaced by the selected contact. Company edits and the original card are kept.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Switch contact'))],
      ));
      if (!mounted || change != true) return;
    }
    setState(() {
      _contact = null;
      for (final contact in _contacts) { if (contact.id == id) _contact = contact; }
      _setFields(SupplierProfile.contact(_contact));
    });
  }

  Future<void> _save() async {
    if (_busy || _supplier == null) return;
    final values = {for (final entry in _controllers.entries) entry.key: entry.value.text.trim()};
    if (values['name']!.isEmpty) { setState(() => _error = 'Supplier name is required.'); return; }
    if (_saveContact && !SupplierProfile.contactFields.keys.any((key) => values[key]!.isNotEmpty)) {
      setState(() => _error = 'Enter at least one contact detail, or switch off Save contact.');
      return;
    }
    final edits = values.entries.where((entry) => entry.value != (_baseline[entry.key] ?? '') &&
        (_saveContact || SupplierProfile.companyFields.containsKey(entry.key))).toList();
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Review supplier changes'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Supplier: ${_supplier!.name}'),
          if (_saveContact) Text(_contact == null ? 'Create a separate contact record.' : 'Update contact: ${_contact!.name}'),
          if (widget.card != null) const Text('Attach this card and retain all previous cards.'),
          if (edits.isEmpty) const Text('No existing field values will change.'),
          for (final entry in edits) Padding(padding: const EdgeInsets.only(top: 12), child: Text(
            '${SupplierProfile.companyFields[entry.key] ?? SupplierProfile.contactFields[entry.key]}\n'
            'Current: ${_baseline[entry.key]?.isNotEmpty == true ? _baseline[entry.key] : "Not recorded"}\n'
            'New: ${entry.value.isEmpty ? "Clear field" : entry.value}')),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back to editing')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save changes'))],
    ));
    if (!mounted || approved != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      final saved = await SupplierProfile.save(original: _supplier!, scope: _scope!, values: values,
        originalContact: _contact, saveContact: _saveContact, card: widget.card);
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) setState(() => _error = error is StateError ? error.message.toString() : 'Save failed. Your edits are still on this screen.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _field(MapEntry<String, String> entry) {
    final incoming = widget.card?.fields[entry.key] ?? '';
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [
      TextField(controller: _controllers[entry.key], enabled: !_busy,
        minLines: 1, maxLines: SupplierProfile.multiline.contains(entry.key) ? 4 : 1,
        decoration: InputDecoration(labelText: entry.value)),
      if (incoming.isNotEmpty && incoming != (_baseline[entry.key] ?? '')) CheckboxListTile(
        contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
        title: Text('Use scanned value: $incoming'),
        subtitle: (_baseline[entry.key]?.isNotEmpty ?? false) ? Text('Existing: ${_baseline[entry.key]}') : null,
        value: _selected.contains(entry.key),
        onChanged: _busy ? null : (selected) => setState(() {
          if (selected == true) { _selected.add(entry.key); } else { _selected.remove(entry.key); }
          _controllers[entry.key]!.text = selected == true ? incoming : _baseline[entry.key] ?? '';
        }),
      ),
    ]));
  }

  @override
  void dispose() { for (final controller in _controllers.values) { controller.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(widget.card == null ? 'Supplier details' : 'Apply card to supplier')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!)),
      if (_supplier != null) ...[
        Text(_supplier!.name, style: Theme.of(context).textTheme.headlineSmall),
        if (widget.card != null) const Text('Blank fields are prefilled. Existing values stay unchanged unless you select or edit a replacement. Review all changes before saving.'),
        const SizedBox(height: 20),
        Text('Company information', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ...SupplierProfile.companyFields.entries.map(_field),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Save contact details'),
          subtitle: const Text('Contacts remain separate people under this supplier.'), value: _saveContact,
          onChanged: _busy ? null : (value) => setState(() => _saveContact = value)),
        if (_saveContact) ...[
          DropdownButtonFormField<int>(key: ValueKey(_contact?.id ?? -1), initialValue: _contact?.id ?? -1,
            isExpanded: true, decoration: const InputDecoration(labelText: 'Contact to update'),
            items: [const DropdownMenuItem(value: -1, child: Text('Add a new contact')),
              for (final contact in _contacts) DropdownMenuItem(value: contact.id!, child: Text(contact.name, overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : (id) => _chooseContact(id == -1 ? null : id)),
          const SizedBox(height: 16),
          ...SupplierProfile.contactFields.entries.map(_field),
        ],
        FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.fact_check_outlined), label: const Text('Review and save')),
        const SizedBox(height: 12),
        const Text('Saved locally. Workspace synchronization and existing team permissions still apply.'),
      ],
    ])),
  ));
}

/// Null means cancelled; -1 selects the existing new-supplier wizard.
Future<int?> chooseCardSupplier(BuildContext context) async {
  return Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => const _CardSupplierPicker()));
}

class _CardSupplierPicker extends StatefulWidget {
  const _CardSupplierPicker();
  @override
  State<_CardSupplierPicker> createState() => _CardSupplierPickerState();
}

class _CardSupplierPickerState extends State<_CardSupplierPicker> {
  late final _suppliers = TradeDatabase.instance.getExhibitors(null);
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Where should this card be saved?')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        FilledButton.icon(onPressed: () => Navigator.pop(context, -1), icon: const Icon(Icons.add), label: const Text('Create a new supplier')),
        const SizedBox(height: 16),
        TextField(decoration: const InputDecoration(labelText: 'Find an existing supplier', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase())),
      ])),
      Expanded(child: FutureBuilder<List<Exhibitor>>(future: _suppliers, builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Could not load suppliers. Reopen this screen to retry.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final matches = snapshot.data!.where((supplier) => '${supplier.name} ${supplier.booth} ${supplier.country}'.toLowerCase().contains(_query)).toList();
        if (matches.isEmpty) return const Center(child: Text('No matching suppliers. You can create a new one.'));
        return ListView.builder(itemCount: matches.length, itemBuilder: (context, index) {
          final supplier = matches[index];
          return ListTile(title: Text(supplier.name), subtitle: Text('Booth ${supplier.booth} | ${supplier.country} | Trip #${supplier.tripId}'),
            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.pop(context, supplier.id));
        });
      })),
    ]),
  );
}
