import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../widgets/voice_note_field.dart';
import 'supplier_voice_note_screen.dart';

class PostFairVisitsScreen extends StatefulWidget {
  const PostFairVisitsScreen({super.key});

  @override
  State<PostFairVisitsScreen> createState() => _PostFairVisitsScreenState();
}

class _PostFairVisitsScreenState extends State<PostFairVisitsScreen> {
  final _db = TradeDatabase.instance;
  late Future<_PostFairVisitData> _data = _load();
  bool _saving = false;

  Future<_PostFairVisitData> _load() async {
    final results = await Future.wait([
      _db.getExhibitors(null),
      _db.getMeetings(),
    ]);
    final suppliers = results[0] as List<Exhibitor>;
    final meetings = results[1] as List<Meeting>;
    return _PostFairVisitData(suppliers, meetings
        .where((meeting) => _details(meeting).isNotEmpty)
        .toList());
  }

  Map<String, dynamic> _details(Meeting meeting) {
    try {
      final value = jsonDecode(meeting.commitmentsJson);
      if (value is Map<String, dynamic> && value['kind'] == 'post_fair_visit') {
        return value;
      }
    } catch (_) {
      // Legacy meeting records remain available, but are not post-fair visits.
    }
    return const {};
  }

  Future<void> _schedule(_PostFairVisitData data) async {
    if (data.suppliers.where((supplier) => supplier.id != null).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Create or sync a supplier before scheduling a visit.')));
      return;
    }
    final draft = await showModalBottomSheet<_PostFairVisitDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PostFairVisitScheduleSheet(suppliers: data.suppliers),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _db.insert('meetings', {
        'exhibitor_id': draft.supplier.id!,
        'meeting_date': draft.when.toIso8601String(),
        'follow_up_date': draft.followUp.toIso8601String(),
        'outcome': 'Post-fair visit scheduled: ${draft.visitType}',
        'priority': draft.priority,
        'notes': draft.objective,
        'assignee_email': draft.owner,
        'commitments_json': jsonEncode({
          'kind': 'post_fair_visit',
          'status': 'Scheduled',
          'title': '${draft.visitType} with ${draft.supplier.name}',
          'visit_type': draft.visitType,
          'location': draft.location,
          'objective': draft.objective,
          'agenda': draft.agenda,
          'internal_attendees': draft.internalAttendees,
          'supplier_attendees': draft.supplierAttendees,
          'pre_visit_checklist': {
            'commercial_background_reviewed': false,
            'questions_prepared': false,
            'products_selected': false,
            'travel_confirmed': false,
          },
          'factory_checklist': <String, bool>{},
          'products_seen': '',
          'capacity_notes': '',
          'quality_notes': '',
          'risks': '',
          'recommendation': '',
          'next_action': '',
        }),
        'completed': 0,
      });
      if (!mounted) return;
      setState(() => _data = _load());
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post-fair visit scheduled.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openVisit(Meeting meeting, Exhibitor supplier) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostFairVisitWorkpadScreen(
              meeting: meeting,
              supplier: supplier,
            )));
    if (mounted) setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Post-fair visits')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving
              ? null
              : () async {
                  final data = await _data;
                  if (mounted) _schedule(data);
                },
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Schedule visit'),
        ),
        body: FutureBuilder<_PostFairVisitData>(
          future: _data,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final supplierById = {for (final supplier in data.suppliers) supplier.id: supplier};
            final scheduled = data.visits.where((item) => !item.completed).toList();
            final completed = data.visits.where((item) => item.completed).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _VisitHero(
                  scheduled: scheduled.length,
                  completed: completed.length,
                ),
                const SizedBox(height: 20),
                _SectionTitle('Upcoming and active visits', scheduled.length),
                if (scheduled.isEmpty)
                  const _EmptyVisits(
                      message: 'Schedule a factory or office visit from a supplier after the fair.'),
                for (final meeting in scheduled)
                  _VisitCard(
                    meeting: meeting,
                    supplier: supplierById[meeting.exhibitorId],
                    details: _details(meeting),
                    onTap: () {
                      final supplier = supplierById[meeting.exhibitorId];
                      if (supplier != null) _openVisit(meeting, supplier);
                    },
                  ),
                const SizedBox(height: 18),
                _SectionTitle('Completed visit reports', completed.length),
                if (completed.isEmpty)
                  const _EmptyVisits(
                      message: 'Completed factory and office reports will remain here for later review.'),
                for (final meeting in completed)
                  _VisitCard(
                    meeting: meeting,
                    supplier: supplierById[meeting.exhibitorId],
                    details: _details(meeting),
                    onTap: () {
                      final supplier = supplierById[meeting.exhibitorId];
                      if (supplier != null) _openVisit(meeting, supplier);
                    },
                  ),
              ],
            );
          },
        ),
      );
}

class PostFairVisitWorkpadScreen extends StatefulWidget {
  const PostFairVisitWorkpadScreen({super.key, required this.meeting, required this.supplier});

  final Meeting meeting;
  final Exhibitor supplier;

  @override
  State<PostFairVisitWorkpadScreen> createState() => _PostFairVisitWorkpadScreenState();
}

class _PostFairVisitWorkpadScreenState extends State<PostFairVisitWorkpadScreen> {
  final _db = TradeDatabase.instance;
  late Map<String, dynamic> _details;
  late TextEditingController _notes;
  late TextEditingController _products;
  late TextEditingController _capacity;
  late TextEditingController _quality;
  late TextEditingController _risks;
  late TextEditingController _nextAction;
  late String _recommendation;
  late Map<String, bool> _checklist;
  bool _saving = false;
  bool _completed = false;

  static const _checklistLabels = {
    'address_confirmed': 'Address and people met confirmed',
    'production_lines_seen': 'Production lines and machinery reviewed',
    'capacity_confirmed': 'Production capacity and shifts confirmed',
    'quality_process_seen': 'Quality-control process reviewed',
    'certificates_checked': 'Certificates and compliance evidence reviewed',
    'samples_or_products_reviewed': 'New products or samples reviewed',
    'packaging_reviewed': 'Packaging and export readiness reviewed',
  };

  @override
  void initState() {
    super.initState();
    try {
      _details = Map<String, dynamic>.from(jsonDecode(widget.meeting.commitmentsJson) as Map);
    } catch (_) {
      _details = {};
    }
    _notes = TextEditingController(text: widget.meeting.notes);
    _products = TextEditingController(text: _details['products_seen'] as String? ?? '');
    _capacity = TextEditingController(text: _details['capacity_notes'] as String? ?? '');
    _quality = TextEditingController(text: _details['quality_notes'] as String? ?? '');
    _risks = TextEditingController(text: _details['risks'] as String? ?? '');
    _nextAction = TextEditingController(text: _details['next_action'] as String? ?? '');
    _recommendation = _details['recommendation'] as String? ?? 'Request quotation';
    _completed = widget.meeting.completed;
    final source = _details['factory_checklist'];
    _checklist = {
      for (final entry in _checklistLabels.keys)
        entry: source is Map && source[entry] == true,
    };
  }

  @override
  void dispose() {
    _notes.dispose();
    _products.dispose();
    _capacity.dispose();
    _quality.dispose();
    _risks.dispose();
    _nextAction.dispose();
    super.dispose();
  }

  Future<void> _save({required bool complete}) async {
    if (widget.meeting.id == null) return;
    setState(() => _saving = true);
    final details = <String, dynamic>{
      ..._details,
      'kind': 'post_fair_visit',
      'status': complete ? 'Completed' : 'In progress',
      'factory_checklist': _checklist,
      'products_seen': _products.text.trim(),
      'capacity_notes': _capacity.text.trim(),
      'quality_notes': _quality.text.trim(),
      'risks': _risks.text.trim(),
      'recommendation': _recommendation,
      'next_action': _nextAction.text.trim(),
      'completed_at': complete ? DateTime.now().toIso8601String() : null,
    };
    try {
      await _db.update('meetings', widget.meeting.id!, {
        'notes': _notes.text.trim(),
        'outcome': complete
            ? 'Post-fair visit completed: $_recommendation'
            : 'Post-fair visit in progress: ${_details['visit_type'] ?? 'Visit'}',
        'follow_up_date': widget.meeting.followUpDate?.toIso8601String(),
        'commitments_json': jsonEncode(details),
        'completed': complete ? 1 : 0,
      });
      if (!mounted) return;
      setState(() {
        _details = details;
        _completed = complete;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(complete ? 'Visit report completed.' : 'Visit workpad saved.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recordAudio() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SupplierVoiceNoteScreen(
              supplier: widget.supplier,
              contextLabel: '${_details['visit_type'] ?? 'Post-fair visit'}: ${widget.supplier.name}',
            )));
  }

  @override
  Widget build(BuildContext context) {
    final type = _details['visit_type'] as String? ?? 'Post-fair visit';
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier.name), actions: [
        IconButton(
          tooltip: 'Record original audio note',
          onPressed: _saving ? null : _recordAudio,
          icon: const Icon(Icons.mic_none_outlined),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(complete: false),
                  child: const Text('Save workpad'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton.icon(
                  onPressed: _saving || _completed ? null : () => _save(complete: true),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: Text(_completed ? 'Completed' : 'Complete visit'))),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          _WorkpadHero(
              type: type,
              date: widget.meeting.meetingDate,
              location: _details['location'] as String? ?? ''),
          const SizedBox(height: 16),
          _WorkpadCard(
            title: 'Visit brief',
            icon: Icons.assignment_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _DetailLine('Objective', _details['objective'] as String? ?? 'Not recorded'),
              _DetailLine('Agenda', _details['agenda'] as String? ?? 'Not recorded'),
              _DetailLine('Supplier attendees', _details['supplier_attendees'] as String? ?? 'Not recorded'),
              _DetailLine('Internal attendees', _details['internal_attendees'] as String? ?? 'Not recorded'),
            ]),
          ),
          _WorkpadCard(
            title: 'Factory and office checklist',
            icon: Icons.fact_check_outlined,
            child: Column(children: [
              for (final entry in _checklistLabels.entries)
                CheckboxListTile(
                  value: _checklist[entry.key] ?? false,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  onChanged: _completed
                      ? null
                      : (value) => setState(() => _checklist[entry.key] = value ?? false),
                ),
            ]),
          ),
          _WorkpadCard(
            title: 'Live notes and products shown',
            icon: Icons.edit_note_outlined,
            child: Column(children: [
              VoiceNoteField(
                controller: _notes,
                label: 'Key findings and supplier statements',
                minLines: 4,
                maxLines: 8,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
              const SizedBox(height: 14),
              VoiceNoteField(
                controller: _products,
                label: 'New products and samples shown',
                minLines: 3,
                maxLines: 6,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
            ]),
          ),
          _WorkpadCard(
            title: 'Capacity, quality and compliance',
            icon: Icons.factory_outlined,
            child: Column(children: [
              VoiceNoteField(
                controller: _capacity,
                label: 'Capacity and production notes',
                minLines: 3,
                maxLines: 5,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
              const SizedBox(height: 14),
              VoiceNoteField(
                controller: _quality,
                label: 'Quality and compliance notes',
                minLines: 3,
                maxLines: 5,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
            ]),
          ),
          _WorkpadCard(
            title: 'Decision and next action',
            icon: Icons.outlined_flag,
            child: Column(children: [
              DropdownButtonFormField<String>(
                initialValue: _recommendation,
                decoration: const InputDecoration(labelText: 'Recommendation'),
                items: const [
                  'Proceed',
                  'Request quotation',
                  'Request sample',
                  'Schedule second visit',
                  'Hold',
                  'Reject',
                ].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: _completed ? null : (value) => setState(() => _recommendation = value!),
              ),
              const SizedBox(height: 14),
              VoiceNoteField(
                controller: _risks,
                label: 'Risks or concerns',
                minLines: 2,
                maxLines: 4,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
              const SizedBox(height: 14),
              VoiceNoteField(
                controller: _nextAction,
                label: 'Next action',
                minLines: 2,
                maxLines: 4,
                enabled: !_completed,
                onRecordAudio: _completed ? null : _recordAudio,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PostFairVisitScheduleSheet extends StatefulWidget {
  const _PostFairVisitScheduleSheet({required this.suppliers});
  final List<Exhibitor> suppliers;

  @override
  State<_PostFairVisitScheduleSheet> createState() => _PostFairVisitScheduleSheetState();
}

class _PostFairVisitScheduleSheetState extends State<_PostFairVisitScheduleSheet> {
  final _objective = TextEditingController();
  final _location = TextEditingController();
  final _agenda = TextEditingController();
  final _internal = TextEditingController();
  final _supplier = TextEditingController();
  final _owner = TextEditingController();
  Exhibitor? _selectedSupplier;
  String _type = 'Factory audit';
  String _priority = 'Medium';
  DateTime _when = DateTime.now().add(const Duration(days: 1, hours: 2));

  @override
  void dispose() {
    _objective.dispose();
    _location.dispose();
    _agenda.dispose();
    _internal.dispose();
    _supplier.dispose();
    _owner.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null || !mounted) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if (_selectedSupplier == null || _objective.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select a supplier and record the visit objective.')));
      return;
    }
    Navigator.pop(
        context,
        _PostFairVisitDraft(
          supplier: _selectedSupplier!,
          visitType: _type,
          priority: _priority,
          when: _when,
          followUp: _when.add(const Duration(days: 2)),
          location: _location.text.trim(),
          objective: _objective.text.trim(),
          agenda: _agenda.text.trim(),
          internalAttendees: _internal.text.trim(),
          supplierAttendees: _supplier.text.trim(),
          owner: _owner.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: ListView(children: [
            Text('Schedule post-fair visit', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text('Plan the visit, then use the live workpad to capture evidence and decisions on site.'),
            const SizedBox(height: 20),
            DropdownButtonFormField<Exhibitor>(
              value: _selectedSupplier,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Supplier'),
              items: widget.suppliers.where((item) => item.id != null).map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
              onChanged: (value) => setState(() => _selectedSupplier = value),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Visit type'),
              items: const ['Factory audit', 'Office meeting', 'Product presentation', 'Capacity review', 'Commercial negotiation', 'Sample review']
                  .map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date and time'),
              subtitle: Text(_formatDateTime(_when)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 8),
            TextField(controller: _location, decoration: const InputDecoration(labelText: 'Factory or office address')),
            const SizedBox(height: 14),
            TextField(controller: _objective, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Visit objective', hintText: 'Discuss cooperation, upcoming products, production capacity or commercial terms')),
            const VoiceNoteAction(contextLabel: 'Post-fair visit objective'),
            const SizedBox(height: 14),
            TextField(controller: _agenda, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Agenda and questions to prepare')),
            const VoiceNoteAction(contextLabel: 'Post-fair visit agenda'),
            const SizedBox(height: 14),
            TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Supplier attendees')),
            const SizedBox(height: 14),
            TextField(controller: _internal, decoration: const InputDecoration(labelText: 'Internal attendees')),
            const SizedBox(height: 14),
            TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Visit owner / assignee')),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const ['High', 'Medium', 'Low']
                  .map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => _priority = value!),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Schedule visit')),
          ]),
        ),
      );
}

class _PostFairVisitData {
  const _PostFairVisitData(this.suppliers, this.visits);
  final List<Exhibitor> suppliers;
  final List<Meeting> visits;
}

class _PostFairVisitDraft {
  const _PostFairVisitDraft({
    required this.supplier,
    required this.visitType,
    required this.priority,
    required this.when,
    required this.followUp,
    required this.location,
    required this.objective,
    required this.agenda,
    required this.internalAttendees,
    required this.supplierAttendees,
    required this.owner,
  });
  final Exhibitor supplier;
  final String visitType;
  final String priority;
  final DateTime when;
  final DateTime followUp;
  final String location;
  final String objective;
  final String agenda;
  final String internalAttendees;
  final String supplierAttendees;
  final String owner;
}

class _VisitHero extends StatelessWidget {
  const _VisitHero({required this.scheduled, required this.completed});
  final int scheduled;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SUPPLIER RELATIONSHIP VISITS', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimary, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Turn fair conversations into confident supplier decisions.', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('$scheduled active visit${scheduled == 1 ? '' : 's'} · $completed completed report${completed == 1 ? '' : 's'}', style: TextStyle(color: scheme.onPrimary.withValues(alpha: .86))),
      ]),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.meeting, required this.supplier, required this.details, required this.onTap});
  final Meeting meeting;
  final Exhibitor? supplier;
  final Map<String, dynamic> details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(supplier?.name ?? 'Supplier unavailable', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                _StatusPill(label: meeting.completed ? 'Completed' : (details['status'] as String? ?? 'Scheduled')),
              ]),
              const SizedBox(height: 6),
              Text(details['visit_type'] as String? ?? 'Post-fair visit'),
              const SizedBox(height: 6),
              Text('${_formatDateTime(meeting.meetingDate)}${(details['location'] as String? ?? '').isEmpty ? '' : ' · ${details['location']}'}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Text(details['objective'] as String? ?? meeting.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

class _WorkpadHero extends StatelessWidget {
  const _WorkpadHero({required this.type, required this.date, required this.location});
  final String type;
  final DateTime date;
  final String location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(type, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSecondaryContainer)),
        const SizedBox(height: 6),
        Text(_formatDateTime(date), style: TextStyle(color: scheme.onSecondaryContainer)),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(location, style: TextStyle(color: scheme.onSecondaryContainer)),
        ],
      ]),
    );
  }
}

class _WorkpadCard extends StatelessWidget {
  const _WorkpadCard({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon), const SizedBox(width: 10), Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count);
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          Text('$count', style: Theme.of(context).textTheme.labelLarge),
        ]),
      );
}

class _EmptyVisits extends StatelessWidget {
  const _EmptyVisits({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 22),
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      );
}

String _formatDateTime(DateTime value) {
  final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} · $hour:$minute $suffix';
}
