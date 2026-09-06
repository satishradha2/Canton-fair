import 'dart:async';

import 'package:flutter/material.dart';

import '../data/business_card_capture.dart';
import '../data/card_ai_service.dart';

class CardAiPanel extends StatefulWidget {
  const CardAiPanel({super.key, required this.draft, required this.enabled,
    required this.onBusyChanged, required this.onChanged});
  final BusinessCardCapture draft;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onChanged;
  @override
  State<CardAiPanel> createState() => _CardAiPanelState();
}

class _CardAiPanelState extends State<CardAiPanel>
    with AutomaticKeepAliveClientMixin<CardAiPanel> {
  @override
  bool get wantKeepAlive => true;

  String _language = 'English';
  String? _error;
  bool _working = false;

  Future<void> _request(bool translateOnly) async {
    if (!widget.enabled || _working) return;
    final consent = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(translateOnly ? 'Translate with OpenAI?' : 'Read this card with OpenAI?'),
      content: Text(translateOnly
          ? 'The original-language card text will be sent to OpenAI through your secured server for translation into $_language. No images are sent for this action. API charges may apply. The translation is a suggestion and does not replace the original.'
          : 'Copies of the front/back images and recognized text will be sent to OpenAI through your secured server. API charges may apply. Only send cards you are authorized to process. OpenAI data-retention policies apply. Originals and manual edits are preserved.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep offline')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send to OpenAI')),
      ],
    ));
    if (!mounted || consent != true || !widget.enabled) return;
    final draft = widget.draft;
    final inputs = draft.imageIdentities;
    final onBusyChanged = widget.onBusyChanged;
    setState(() { _working = true; _error = null; });
    onBusyChanged(true);
    try {
      final result = await CardAiService.read(draft, translateOnly: translateOnly, language: _language);
      result['input_files'] = inputs;
      draft.aiReadings.add(result);
      try {
        await draft.save().timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw StateError('AI reading finished, but saving the local draft is taking too long. The result is shown below; check free storage before leaving. Do not repeat the paid request.');
      }
      if (mounted) widget.onChanged();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString() : 'Cloud reading is unavailable. Your local card is unchanged.');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
      // The screen callback checks its own mounted state, even if this panel
      // was removed while awaiting a platform or network operation.
      onBusyChanged(false);
    }
  }

  Future<void> _apply(Map<String, dynamic> reading, {String? field}) async {
    if (!widget.enabled || !widget.draft.matchesAi(reading)) return;
    final suggestions = reading['fields'] as Map? ?? {};
    if (field != null && (widget.draft.fields[field]?.trim().isNotEmpty ?? false)) {
      final replace = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Replace this reviewed field?'),
        content: Text('Current: ${widget.draft.fields[field]}\n\nAI suggestion: ${suggestions[field]}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep current')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use suggestion'))],
      ));
      if (!mounted || replace != true) return;
    }
    for (final entry in suggestions.entries) {
      final key = entry.key as String;
      final value = entry.value as String;
      if (value.trim().isEmpty || (field != null && key != field)) continue;
      if (field == null && (widget.draft.fields[key]?.trim().isNotEmpty ?? false)) continue;
      widget.draft.fields[key] = value;
      widget.draft.edited.add(key);
    }
    try {
      await widget.draft.save();
      if (mounted) widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not persist the suggestions. Check local storage.');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final history = widget.draft.aiReadings;
    final latest = history.isEmpty ? null : history.last;
    final current = latest != null && widget.draft.matchesAi(latest);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('OpenAI reading and translation', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Optional online processing. Nothing is uploaded automatically. Review suggestions before using them; original text and images stay intact.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _language, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Translate into'),
          items: CardAiService.languages.map((language) => DropdownMenuItem(value: language, child: Text(language))).toList(),
          onChanged: widget.enabled ? (value) => setState(() => _language = value ?? _language) : null),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: widget.enabled && widget.draft.sides.isNotEmpty ? () => _request(false) : null,
            icon: const Icon(Icons.auto_awesome_outlined), label: const Text('AI extract + translate')),
          OutlinedButton(onPressed: widget.enabled && widget.draft.sides.keys.any((side) => widget.draft.translationSource(side).trim().isNotEmpty)
              ? () => _request(true) : null, child: const Text('Translate text only')),
        ]),
        if (_working) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Waiting for OpenAI. Requests are not retried automatically.')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true, child: Text(_error!))),
        if (latest != null) ...[
          const Divider(),
          Text('Latest reading: ${latest['model']} / ${latest['target_language']}'),
          if (!current) const Text('The images have changed since this reading. Run AI extraction again before applying suggestions.'),
          for (final warning in latest['warnings'] as List? ?? []) Text(warning.toString()),
          if (latest['operation'] == 'extract') ...[
            TextButton(onPressed: widget.enabled && current ? () => _apply(latest) : null, child: const Text('Fill blank fields only')),
            ExpansionTile(title: const Text('Review extracted suggestions'), children: [
              for (final entry in (latest['fields'] as Map).entries)
                if (entry.value.toString().trim().isNotEmpty) ListTile(
                  title: Text(entry.key.toString()), subtitle: SelectableText(entry.value.toString()),
                  trailing: TextButton(onPressed: widget.enabled && current ? () => _apply(latest, field: entry.key as String) : null,
                    child: const Text('Use')),
                ),
              for (final item in latest['extra_details'] as List? ?? [])
                ListTile(title: Text(item['label'] as String), subtitle: SelectableText(item['value'] as String)),
            ]),
          ],
          ExpansionTile(title: const Text('Original transcript and translation'), children: [
            for (final side in widget.draft.sides.keys) ListTile(
              title: Text(side), subtitle: SelectableText(
                'Original:\n${(latest['transcript'] as Map)[side] ?? ''}\n\nTranslation:\n${(latest['translation'] as Map)[side] ?? ''}'),
            ),
          ]),
          Text('${history.length} cloud reading(s) preserved with this card.'),
        ],
      ],
    )));
  }
}
