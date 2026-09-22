import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/sync_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';
import '../widgets/voice_note_field.dart';
import 'hall_route_screen.dart';
import 'ocr_screen.dart';
import 'sync_status_screen.dart';

/// A field-first workpad that keeps the visit sequence visible and directs
/// durable capture to the existing offline supplier, OCR and sync workflows.
class FieldVisitAssistantScreen extends StatefulWidget {
  const FieldVisitAssistantScreen({super.key});

  @override
  State<FieldVisitAssistantScreen> createState() =>
      _FieldVisitAssistantScreenState();
}

class _FieldVisitAssistantScreenState extends State<FieldVisitAssistantScreen> {
  final _supplier = TextEditingController();
  final _booth = TextEditingController();
  final _note = TextEditingController();
  final _handover = TextEditingController();
  final _sample = TextEditingController();
  final _followUpDate = TextEditingController();

  int _tab = 0;
  DateTime? _checkedInAt;
  bool _boothVisited = false;
  bool _brochureReceived = false;
  bool _followUpRequired = false;
  bool _sampleReceived = false;
  bool _scanReviewed = false;
  bool _photoLinked = false;
  String _followUpType = 'Request quotation';

  @override
  void dispose() {
    _supplier.dispose();
    _booth.dispose();
    _note.dispose();
    _handover.dispose();
    _sample.dispose();
    _followUpDate.dispose();
    super.dispose();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      _followUpDate.text =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    });
  }

  String get _visitSummary {
    final supplier = _supplier.text.trim().isEmpty
        ? 'Supplier not recorded'
        : _supplier.text.trim();
    final booth = _booth.text.trim().isEmpty ? 'Booth not recorded' : _booth.text.trim();
    final checkIn = _checkedInAt == null
        ? 'Not checked in'
        : 'Checked in ${TimeOfDay.fromDateTime(_checkedInAt!).format(context)}';
    return '''FIELD VISIT REPORT
Supplier: $supplier
Booth: $booth
$checkIn
Booth visited: ${_boothVisited ? 'Yes' : 'No'}
Card/OCR reviewed: ${_scanReviewed ? 'Yes' : 'No'}
Product/photo linked: ${_photoLinked ? 'Yes' : 'No'}
Brochure received: ${_brochureReceived ? 'Yes' : 'No'}
Sample: ${_sampleReceived ? _sample.text.trim().ifEmpty('Received') : 'None'}
Next action: ${_followUpRequired ? '$_followUpType ${_followUpDate.text}'.trim() : 'None'}
Notes: ${_note.text.trim().ifEmpty('None')}
Handover: ${_handover.text.trim().ifEmpty('None')}''';
  }

  bool get _readyToComplete =>
      _supplier.text.trim().isNotEmpty && _boothVisited && _scanReviewed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guided field visit')),
      body: SafeArea(
        child: Column(children: [
          _syncBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.place_outlined), label: Text('Visit')),
                ButtonSegment(value: 1, icon: Icon(Icons.add_a_photo_outlined), label: Text('Capture')),
                ButtonSegment(value: 2, icon: Icon(Icons.task_alt_outlined), label: Text('Complete')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_tab == 0) ..._visitTab(),
                if (_tab == 1) ..._captureTab(),
                if (_tab == 2) ..._completeTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _syncBanner() => ValueListenableBuilder<int>(
        valueListenable: SyncStatusService.changes,
        builder: (context, _, __) => FutureBuilder<SyncStatus>(
          future: SyncStatusService().load(),
          builder: (context, snapshot) {
            final status = snapshot.data ?? const SyncStatus();
            final needsAttention = snapshot.hasError ||
                status.lastError != null ||
                status.conflicts > 0;
            final color = needsAttention ? AppColors.danger : AppColors.teal;
            final label = needsAttention
                ? '${status.conflicts} sync item${status.conflicts == 1 ? '' : 's'} needs attention'
                : status.lastSyncedAt == null
                    ? 'Offline-ready: records are saved on this device'
                    : 'Sync healthy: field records are protected';
            return Material(
              color: color.withValues(alpha: 0.10),
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SyncStatusScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(needsAttention ? Icons.sync_problem : Icons.cloud_done_outlined,
                        color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label,
                        style: TextStyle(color: color, fontWeight: FontWeight.w700))),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  List<Widget> _visitTab() => [
        _section(
          title: '1. Check in',
          subtitle: 'Keep the most important visit facts accessible with one hand.',
          child: Column(children: [
            TextField(
              controller: _supplier,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Supplier name',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _booth,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Hall / booth',
                hintText: 'Example: 1A-F28',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              ElevatedButton.icon(
                onPressed: () => setState(() {
                  _checkedInAt = DateTime.now();
                  _boothVisited = true;
                }),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(_checkedInAt == null ? 'Check in at booth' : 'Checked in'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HallRouteScreen())),
                icon: const Icon(Icons.route_outlined),
                label: const Text('Find next booth'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Visit checklist',
          subtitle: 'A short checklist prevents lost samples, brochures, and next actions.',
          child: Column(children: [
            _check('Booth visited', _boothVisited, (v) => setState(() => _boothVisited = v)),
            _check('Sample received', _sampleReceived, (v) => setState(() => _sampleReceived = v)),
            if (_sampleReceived)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 8),
                child: TextField(
                  controller: _sample,
                  decoration: const InputDecoration(
                    labelText: 'Sample description / quantity',
                    hintText: 'Example: 2 colour swatches, courier required',
                  ),
                ),
              ),
            _check('Brochure or catalogue received', _brochureReceived,
                (v) => setState(() => _brochureReceived = v)),
            _check('Follow-up required', _followUpRequired,
                (v) => setState(() => _followUpRequired = v)),
          ]),
        ),
      ];

  List<Widget> _captureTab() => [
        _section(
          title: '2. Capture durable evidence',
          subtitle: 'Use the established offline capture tools so photos and data stay linked to supplier records.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _largeAction(
              Icons.document_scanner_outlined,
              'Review business card OCR',
              'Correct uncertain card fields beside the source image before saving.',
              () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const OcrScreen()));
                if (mounted) setState(() => _scanReviewed = true);
              },
            ),
            const SizedBox(height: 10),
            _largeAction(
              Icons.photo_camera_outlined,
              'Link product photo or catalogue',
              'Use supplier/product capture to retain photos, catalogues, and brochures against the supplier.',
              () {
                setState(() => _photoLinked = true);
                _message('Open Field capture to add the photo, catalogue, or product to this supplier.');
              },
            ),
            const SizedBox(height: 10),
            _largeAction(
              Icons.record_voice_over_outlined,
              'Voice-to-note reminder',
              'Record your discussion in the field capture workflow, then keep the decision note below.',
              () => _message('Use the voice note action in Field capture, then return to finish this visit.'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Decision note',
          subtitle: 'Visible to the next team member and included in your handover.',
          child: TextField(
            controller: _note,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              hintText: 'Price position, product fit, quality observations, decision, or risks...',
              alignLabelWithHint: true,
            ),
          ),
          const VoiceNoteAction(contextLabel: 'Field visit decision note'),
        ),
      ];

  List<Widget> _completeTab() => [
        _section(
          title: '3. Follow up and hand over',
          subtitle: 'Turn the visit into a clear owner, action, and deadline.',
          child: Column(children: [
            if (_followUpRequired) ...[
              DropdownButtonFormField<String>(
                initialValue: _followUpType,
                decoration: const InputDecoration(labelText: 'Next action'),
                items: const [
                  DropdownMenuItem(value: 'Request quotation', child: Text('Request quotation')),
                  DropdownMenuItem(value: 'Call supplier', child: Text('Call supplier')),
                  DropdownMenuItem(value: 'Send email', child: Text('Send email')),
                  DropdownMenuItem(value: 'Request sample', child: Text('Request sample')),
                  DropdownMenuItem(value: 'Review catalogue', child: Text('Review catalogue')),
                ],
                onChanged: (value) => setState(() => _followUpType = value ?? _followUpType),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _followUpDate,
                readOnly: true,
                onTap: _chooseFollowUpDate,
                decoration: const InputDecoration(
                  labelText: 'Follow-up due date',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _handover,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Team handover / assigned colleague',
                hintText: 'Example: Priya to request samples by Thursday',
                prefixIcon: Icon(Icons.group_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const VoiceNoteAction(contextLabel: 'Field visit handover note'),
          ]),
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Finish safely',
          subtitle: _readyToComplete
              ? 'This visit has the minimum information needed to continue safely.'
              : 'Before finishing: record supplier, check in at the booth, and review the business card.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ElevatedButton.icon(
              onPressed: _readyToComplete
                  ? () {
                      Clipboard.setData(ClipboardData(text: _visitSummary));
                      _message('Visit report copied. Save the supplier record in Field capture before leaving.');
                    }
                  : null,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy emergency visit report'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SyncStatusScreen())),
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Review offline sync and conflicts'),
            ),
          ]),
        ),
      ];

  Widget _section({required String title, required String subtitle, required Widget child}) =>
      SectionPanel(title: title, subtitle: subtitle, child: child);

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label),
        value: value,
        onChanged: (value) => onChanged(value ?? false),
      );

  Widget _largeAction(IconData icon, String title, String subtitle, VoidCallback onTap) =>
      Material(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: AppColors.teal, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ])),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
