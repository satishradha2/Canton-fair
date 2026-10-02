import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/company_visit_service.dart';
import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/reminder_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../widgets/company_products_section.dart';
import '../widgets/company_visit_evidence.dart';
import 'supplier_contacts_screen.dart';

class CompanyVisitsScreen extends StatefulWidget {
  const CompanyVisitsScreen({super.key, this.company, this.fairId});
  final Exhibitor? company;
  final int? fairId;
  @override
  State<CompanyVisitsScreen> createState() => _CompanyVisitsScreenState();
}
class _CompanyVisitsScreenState extends State<CompanyVisitsScreen> {
  String? _scope, _error;
  bool _loading = true, _canEdit = false;
  List<Map<String, Object?>> _rows = [];
  List<Map<String, dynamic>> _drafts = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final scope = await TeamWorkspaceService().scopeKey();
      final rows = await CompanyVisitService.list(scope, company: widget.company?.id);
      final drafts = widget.company == null ? <Map<String, dynamic>>[] : await CompanyVisitService.unfinished(scope, widget.company!.id!);
      bool canEdit = false;
      try { canEdit = await ProductCaptureService.canWrite(); } catch (_) { /* Read-only until role available. */ }
      await ProductCaptureService.checkScope(scope);
      if (mounted) setState(() { _scope = scope; _rows = rows; _drafts = drafts; _canEdit = canEdit; _error = null; _loading = false; });
    } catch (error) { if (mounted) setState(() { _error = '$error'; _loading = false; }); }
  }
  Future<void> _open([Map<String, Object?>? row, String? draftKey]) async {
    try {
      await ProductCaptureService.checkScope(_scope!);
      final company = widget.company ?? await TradeDatabase.instance.getExhibitorById(row!['exhibitor_id'] as int);
      if (!mounted || company == null) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyVisitWorkpadScreen(scope: _scope!, company: company,
        appointment: row, canEdit: _canEdit, fairId: widget.fairId, draftKey: draftKey)));
      if (mounted) await _load();
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }
  Widget _list(bool history) {
    final rows = _rows.where((row) => ['Completed', 'Cancelled'].contains(CompanyVisitService.details(row)['status']) == history).toList();
    if (rows.isEmpty) return Center(child: Text(history ? 'No completed or cancelled visits yet.' : 'No upcoming visits. Schedule one from a company page.'));
    return ListView.builder(padding: const EdgeInsets.all(20), itemCount: rows.length, itemBuilder: (context, index) {
      final row = rows[index]; final data = CompanyVisitService.details(row);
      final at = DateTime.tryParse(row['meeting_date'].toString());
      return Card(child: ListTile(contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(child: Icon(data['type'] == 'Factory' ? Icons.factory_outlined : Icons.apartment_outlined)),
        title: Text('${row['company_name']} - ${data['type']} visit'),
        subtitle: Text('${data['wall_time'].toString().replaceAll('T', ' ')} (${data['zone']})\n${data['status']}${!history && at != null && at.isBefore(DateTime.now()) ? ' - appointment time has passed' : ''}\n${data['purpose']}'),
        trailing: const Icon(Icons.chevron_right), onTap: () => _open(row)));
    });
  }
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 2, child: Scaffold(
    appBar: AppBar(title: const Text('Visits & appointments'), actions: [IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      bottom: const TabBar(tabs: [Tab(text: 'Upcoming / active'), Tab(text: 'History')])),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!)) : Column(children: [
      if (widget.company != null) Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.company!.name, style: Theme.of(context).textTheme.titleLarge),
        if (_canEdit && _drafts.isNotEmpty) DropdownButtonFormField<String>(
          key: ValueKey(_drafts.map((draft) => draft['visit_key']).join(',')),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Resume unfinished appointment', helperText: 'Drafts are saved on this phone, not yet shared through Sync.'),
          items: _drafts.map((draft) => DropdownMenuItem(value: draft['visit_key'] as String,
            child: Text('${draft['type']} - ${(draft['wall_time'] ?? '').toString().isEmpty ? 'Time not chosen' : draft['wall_time']} - ${draft['purpose'] ?? ''}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (key) { if (key != null) _open(null, key); },
        ),
        if (_canEdit) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Schedule factory / office visit'))),
      ])),
      Expanded(child: TabBarView(children: [_list(false), _list(true)])),
    ]),
  ));
}

class CompanyVisitWorkpadScreen extends StatefulWidget {
  const CompanyVisitWorkpadScreen({super.key, required this.scope, required this.company, required this.canEdit, this.appointment, this.fairId, this.draftKey});
  final String scope;
  final Exhibitor company;
  final bool canEdit;
  final Map<String, Object?>? appointment;
  final int? fairId;
  final String? draftKey;
  @override
  State<CompanyVisitWorkpadScreen> createState() => _CompanyVisitWorkpadScreenState();
}
class _CompanyVisitWorkpadScreenState extends State<CompanyVisitWorkpadScreen> {
  static const labels = {'address': 'Factory / office address', 'map_link': 'Map link (optional)',
    'purpose': 'Purpose / objectives', 'duration': 'Expected duration in minutes', 'attendees': 'Attending team members (names / emails)',
    'discussion': 'Discussion and supplier statements', 'products_notes': 'New products / samples discussed',
    'capacity': 'Machinery, capacity and production processes', 'quality': 'Quality checks, compliance and certificates',
    'cooperation': 'Pricing, payment terms and cooperation', 'outcome': 'Visit outcome and key findings'};
  final _fields = <String, TextEditingController>{};
  final _form = GlobalKey<FormState>();
  late String _visitKey;
  int? _id;
  int _revision = 0, _reminder = 60;
  String _type = 'Factory', _status = 'Tentative', _zone = 'Asia/Shanghai';
  String _wallTime = '', _contact = '', _contactEmail = '', _contactPhone = '';
  List<Contact> _contacts = [];
  List<Map<String, dynamic>> _actions = [];
  bool _loading = true, _busy = false, _allowExit = false;
  String? _error;
  String _draftMessage = 'Save appointment to open your visit workspace.';
  Timer? _timer;
  Future<void> _writes = Future.value();
  TextEditingController _field(String key) => _fields.putIfAbsent(key, () => TextEditingController());
  @override
  void initState() {
    super.initState();
    _id = widget.appointment?['id'] as int?;
    final initial = widget.appointment == null ? <String, dynamic>{} : CompanyVisitService.details(widget.appointment!);
    _visitKey = widget.draftKey ?? initial['visit_key']?.toString() ?? 'visit-${DateTime.now().microsecondsSinceEpoch}-${Supabase.instance.client.auth.currentUser?.id ?? 'local'}';
    _load(initial);
  }
  Future<void> _load(Map<String, dynamic> initial) async {
    try {
      _contacts = await TradeDatabase.instance.getContacts(widget.company.id!);
      _revision = (initial['revision'] as num?)?.toInt() ?? 0;
      final draft = widget.canEdit ? await CompanyVisitService.loadDraft(widget.scope, _visitKey) : null;
      final data = draft != null && draft['revision'] == _revision ? draft : initial;
      if (draft != null && draft['revision'] != _revision) {
        _draftMessage = 'An older draft exists; it was not applied over the latest record.';
      } else if (draft != null) {
        _draftMessage = 'Unfinished workpad restored from this phone.';
      }
      for (final key in labels.keys) { _field(key).text = data[key]?.toString() ?? ''; }
      if (_field('duration').text.isEmpty) _field('duration').text = '60';
      _type = data['type']?.toString() ?? 'Factory'; _status = data['status']?.toString() ?? 'Tentative';
      _zone = data['zone']?.toString() ?? 'Asia/Shanghai'; _wallTime = data['wall_time']?.toString() ?? '';
      _contact = data['contact_name']?.toString() ?? ''; _contactEmail = data['contact_email']?.toString() ?? ''; _contactPhone = data['contact_phone']?.toString() ?? '';
      _reminder = (data['reminder_minutes'] as num?)?.toInt() ?? 60;
      _actions = (data['actions'] as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      if (mounted) setState(() => _loading = false);
    } catch (error) { if (mounted) setState(() { _loading = false; _error = '$error'; }); }
  }
  Map<String, dynamic> _data() => {'visit_key': _visitKey, 'revision': _revision,
    'company_id': widget.company.id, 'appointment_id': _id,
    'type': _type, 'status': _status, 'zone': _zone, 'wall_time': _wallTime,
    'contact_name': _contact, 'contact_email': _contactEmail, 'contact_phone': _contactPhone,
    'reminder_minutes': _reminder, 'actions': _actions.map((item) => Map<String, dynamic>.from(item)).toList(),
    for (final key in labels.keys) key: _field(key).text.trim()};
  void _changed() {
    if (!widget.canEdit) return;
    _timer?.cancel(); _timer = Timer(const Duration(milliseconds: 650), _queueDraft);
  }
  void _queueDraft() {
    final data = _data();
    _writes = _writes.then((_) async {
      try { await CompanyVisitService.draft(widget.scope, _visitKey, data); if (mounted) setState(() => _draftMessage = 'Draft saved on this phone. Save workpad to include it in Sync.'); }
      catch (error) { if (mounted) setState(() => _draftMessage = 'Draft could not save: $error'); }
    });
  }
  Future<void> _leave() async {
    if (_busy) return;
    if (widget.canEdit) { _timer?.cancel(); _queueDraft(); await _writes; }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
  }
  Future<void> _pickTime() async {
    final initial = DateTime.tryParse(_wallTime) ?? DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    setState(() => _wallTime = DateTime(date.year, date.month, date.day, time.hour, time.minute).toIso8601String()); _changed();
  }
  int get _notificationId => int.parse(sha256.convert(utf8.encode('${widget.scope}:$_visitKey')).toString().substring(0, 7), radix: 16) + 500000000;
  Future<void> _save({String? status}) async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_wallTime.isEmpty || _contact.isEmpty) { setState(() => _error = 'Choose appointment date/time and a contact.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      _timer?.cancel(); _queueDraft(); await _writes;
      final data = _data();
      if (status != null) {
        data['status'] = status;
      }
      final saved = await CompanyVisitService.save(widget.scope, widget.company.id!, _id, data, _revision);
      _id = saved['id'] as int; _revision++; _status = data['status'] as String;
      await CompanyVisitService.clearDraft(widget.scope, _visitKey);
      String message = 'Visit saved locally. Use Sync to share with your team.';
      try {
        await ReminderService.initialize();
        await ReminderService.cancel(_notificationId);
        if (_reminder > 0 && ['Tentative', 'Confirmed'].contains(_status)) {
          final at = CompanyVisitService.instant(_wallTime, _zone).subtract(Duration(minutes: _reminder));
          if (at.isAfter(DateTime.now())) {
            await ReminderService.scheduleFollowUp(id: _notificationId,
              title: '$_type visit: ${widget.company.name}', body: '${_field('address').text}\n$_wallTime ($_zone)', at: at, payload: 'company-visit:$_visitKey');
          }
        }
      } catch (_) { message += ' Reminder could not be scheduled; check notification permissions.'; }
      if (mounted) setState(() => _draftMessage = message);
    } catch (error) { if (mounted) setState(() => _error = 'Could not save visit: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _action() async {
    final task = TextEditingController(), owner = TextEditingController(text: Supabase.instance.client.auth.currentUser?.email ?? '');
    DateTime? due;
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('Add agreed action'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: task, decoration: const InputDecoration(labelText: 'Action / request')),
        TextField(controller: owner, decoration: const InputDecoration(labelText: 'Responsible person / email')),
        TextButton(onPressed: () async {
          final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (date != null && context.mounted) update(() => due = date);
        }, child: Text(due == null ? 'Choose deadline' : due.toString().split(' ').first)),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (task.text.trim().isNotEmpty && owner.text.trim().isNotEmpty && due != null) Navigator.pop(context, true); }, child: const Text('Add'))],
    )));
    if (accepted == true && mounted) { setState(() => _actions.add({'task': task.text.trim(), 'owner': owner.text.trim(), 'due': due!.toIso8601String().split('T').first, 'done': false})); _changed(); }
    Future<void>.delayed(const Duration(milliseconds: 400), () { task.dispose(); owner.dispose(); });
  }
  Future<void> _linkProducts() async {
    try {
      final products = await TradeDatabase.instance.getProducts(widget.company.id!);
      if (!mounted) return;
      final selected = <int>{};
      final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Link existing company products'), content: SizedBox(width: double.maxFinite, child: products.isEmpty ? const Text('No saved products yet. Add a product below.') : ListView(shrinkWrap: true, children: [for (final product in products) CheckboxListTile(title: Text(product.name), value: selected.contains(product.id), onChanged: (value) => update(() {
          if (value == true) {
            selected.add(product.id!);
          } else {
            selected.remove(product.id);
          }
        }))])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Link selected'))],
      )));
      if (accepted != true) return;
      for (final id in selected) { await CompanyVisitService.linkProduct(widget.scope, widget.company.id!, id, _visitKey); }
      if (mounted) setState(() => _productRefresh++);
    } catch (error) { if (mounted) setState(() => _error = 'Could not link products: $error'); }
  }
  int _productRefresh = 0;
  Future<void> _reviewShortlists() async {
    _timer?.cancel();
    if (widget.canEdit) {
      _queueDraft();
      await _writes;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierContactsScreen(
      companyId: widget.company.id, fairId: widget.fairId)));
  }
  Future<void> _map() async {
    try {
      final text = _field('map_link').text.trim();
      final uri = text.isEmpty ? Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': _field('address').text}) : Uri.parse(text);
      if (!['http', 'https'].contains(uri.scheme) || !await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('Could not open map.');
    } catch (error) { if (mounted) setState(() => _error = '$error'); }
  }
  Widget _input(String key, {bool required = false}) => Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(
    controller: _field(key), enabled: widget.canEdit && !_busy, onChanged: (_) => _changed(), minLines: 1,
    maxLines: ['duration', 'map_link', 'attendees'].contains(key) ? 1 : 5,
    keyboardType: key == 'duration' ? TextInputType.number : TextInputType.multiline,
    decoration: InputDecoration(labelText: labels[key], border: const OutlineInputBorder()),
    validator: required ? (value) => value == null || value.trim().isEmpty ? 'Required' : null : null));
  Widget _section(String title, String key) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16), _input(key),
    CompanyVisitEvidence(scope: widget.scope, company: widget.company, visitKey: _visitKey, section: title, canEdit: widget.canEdit && !_busy && _status == 'In progress'),
  ])));
  @override
  void dispose() { _timer?.cancel(); for (final field in _fields.values) { field.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: _allowExit, onPopInvokedWithResult: (didPop, result) { if (!didPop) _leave(); }, child: Scaffold(
    appBar: AppBar(title: Text('${widget.company.name} - visit'), actions: [if (_id != null) IconButton(tooltip: 'Share visit summary', icon: const Icon(Icons.share_outlined), onPressed: () => SharePlus.instance.share(ShareParams(text: '${widget.company.name}\n$_type visit - $_status\n$_wallTime ($_zone)\nContact: $_contact\n${labels.entries.map((entry) => '${entry.value}: ${_field(entry.key).text}').join('\n')}\nActions:\n${_actions.map((action) => '${action['task']} | ${action['owner']} | ${action['due']} | ${action['done'] == true ? 'Done' : 'Pending'}').join('\n')}')))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : Form(key: _form, child: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Appointment', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), Text('Status: $_status'), const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Visit type'), items: ['Factory', 'Office'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: widget.canEdit && !_busy ? (value) { setState(() => _type = value!); _changed(); } : null),
          if (!['In progress', 'Completed', 'Cancelled'].contains(_status)) DropdownButtonFormField<String>(key: ValueKey(_status), initialValue: _status, decoration: const InputDecoration(labelText: 'Confirmation'), items: ['Tentative', 'Confirmed'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: widget.canEdit && !_busy ? (value) { setState(() => _status = value!); _changed(); } : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: _zone, isExpanded: true, decoration: const InputDecoration(labelText: 'Appointment time zone'), items: CompanyVisitService.timeZones().map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(), onChanged: widget.canEdit && !_busy ? (value) { setState(() => _zone = value!); _changed(); } : null),
          OutlinedButton.icon(onPressed: widget.canEdit && !_busy ? _pickTime : null, icon: const Icon(Icons.event_outlined), label: Text(_wallTime.isEmpty ? 'Choose date and time' : _wallTime.replaceAll('T', ' '))),
          DropdownButtonFormField<int>(decoration: InputDecoration(labelText: _contact.isEmpty ? 'Company contact (required)' : 'Contact: $_contact'), items: _contacts.map((contact) => DropdownMenuItem(value: contact.id!, child: Text(contact.name))).toList(), onChanged: widget.canEdit && !_busy ? (id) { final contact = _contacts.firstWhere((item) => item.id == id); setState(() { _contact = contact.name; _contactEmail = contact.email; _contactPhone = contact.phone; }); _changed(); } : null),
          if (_contact.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text([_contact, _contactPhone, _contactEmail].where((item) => item.isNotEmpty).join('\n'))),
          _input('address', required: true), _input('map_link'), OutlinedButton.icon(onPressed: _map, icon: const Icon(Icons.map_outlined), label: const Text('Open map / directions')),
          _input('purpose', required: true), _input('duration', required: true), _input('attendees'),
          DropdownButtonFormField<int>(initialValue: _reminder, decoration: const InputDecoration(labelText: 'Reminder on this phone'), items: [0, 15, 30, 60, 1440].map((value) => DropdownMenuItem(value: value, child: Text(value == 0 ? 'No reminder' : '$value minutes before'))).toList(), onChanged: widget.canEdit && !_busy ? (value) { setState(() => _reminder = value!); _changed(); } : null),
          if (_id != null) CompanyVisitEvidence(scope: widget.scope, company: widget.company, visitKey: _visitKey, section: 'Appointment objectives', canEdit: widget.canEdit && !_busy && !['Completed', 'Cancelled'].contains(_status)),
          const SizedBox(height: 12), Text(_draftMessage), if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]))),
        if (_id != null) ...[
          if (widget.canEdit && ['Tentative', 'Confirmed'].contains(_status)) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.icon(onPressed: _busy ? null : () => _save(status: 'In progress'), icon: const Icon(Icons.play_arrow), label: const Text('Start visit'))),
          _section('Discussion', 'discussion'), _section('New products and samples', 'products_notes'),
          if (_type == 'Factory') _section('Production capacity', 'capacity'),
          _section('Quality and compliance', 'quality'), _section('Cooperation and commercial terms', 'cooperation'),
          if (widget.canEdit && _status == 'In progress') TextButton.icon(onPressed: _busy ? null : _linkProducts, icon: const Icon(Icons.link), label: const Text('Link existing products to this visit')),
          CompanyProductsSection(key: ValueKey(_productRefresh), scope: widget.scope, company: widget.company, canEdit: widget.canEdit && !_busy && _status == 'In progress', fairId: widget.fairId ?? widget.company.tripId, visitKey: _visitKey),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Agreed actions and deadlines', style: Theme.of(context).textTheme.titleLarge),
            for (final action in _actions) CheckboxListTile(contentPadding: EdgeInsets.zero, value: action['done'] == true,
              title: Text(action['task'].toString()), subtitle: Text('${action['owner']} - Due ${action['due']}'),
              onChanged: widget.canEdit && !_busy ? (value) { setState(() => action['done'] = value == true); _changed(); } : null),
            if (widget.canEdit && !['Completed', 'Cancelled'].contains(_status)) TextButton.icon(onPressed: _busy ? null : _action, icon: const Icon(Icons.add_task), label: const Text('Add action / sample / quotation request')),
            _input('outcome'),
            CompanyVisitEvidence(scope: widget.scope, company: widget.company, visitKey: _visitKey, section: 'Outcome and agreed actions', canEdit: widget.canEdit && !_busy && _status == 'In progress'),
            TextButton(onPressed: _reviewShortlists, child: const Text('Review company and product shortlists')),
            if (widget.canEdit && _status == 'Completed') TextButton(onPressed: _busy ? null : () => _save(status: 'In progress'), child: const Text('Reopen visit')),
            if (widget.canEdit && _status == 'Completed') TextButton.icon(icon: const Icon(Icons.event_repeat), label: const Text('Schedule another visit'), onPressed: _busy ? null : () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyVisitWorkpadScreen(scope: widget.scope, company: widget.company, canEdit: widget.canEdit, fairId: widget.fairId)));
            }),
          ]))),
        ],
      ])),
      if (widget.canEdit) SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : () => _save(), icon: const Icon(Icons.save_outlined), label: Text(_id == null ? 'Save appointment' : 'Save workpad')),
        if (_status == 'In progress') FilledButton.icon(onPressed: _busy ? null : () => _save(status: 'Completed'), icon: const Icon(Icons.check_circle_outline), label: const Text('Complete visit')),
        if (_id != null && ['Tentative', 'Confirmed'].contains(_status)) TextButton(onPressed: _busy ? null : () => _save(status: 'Cancelled'), child: const Text('Cancel appointment')),
      ]))),
    ])),
  ));
}
