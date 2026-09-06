import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../models/models.dart';

class BusinessCardArchiveScreen extends StatefulWidget {
  const BusinessCardArchiveScreen({super.key, required this.supplierId, required this.archive});

  final int supplierId;
  final Map<String, dynamic> archive;

  @override
  State<BusinessCardArchiveScreen> createState() => _BusinessCardArchiveScreenState();
}

class _BusinessCardArchiveScreenState extends State<BusinessCardArchiveScreen> {
  late final Future<List<Attachment>> _images =
      TradeDatabase.instance.getAttachments('exhibitor', widget.supplierId);

  String get _transcript {
    final fields = widget.archive['fields'] as Map? ?? {};
    return [
      for (final entry in fields.entries)
        if (entry.value.toString().trim().isNotEmpty) '${entry.key}: ${entry.value}',
      '', 'Original recognized text:', widget.archive['raw_text'] as String? ?? '',
    ].join('\n');
  }

  Future<void> _share() async {
    try {
      final images = await _images;
      final files = <XFile>[];
      for (final item in images) {
        if (item.note.endsWith(' | ${widget.archive['id']}') && await File(item.path).exists()) {
          files.add(XFile(item.path));
        }
      }
      await SharePlus.instance.share(ShareParams(
        title: 'Business card', text: _transcript,
        files: files.isEmpty ? null : files,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share the card. Try copying the text instead.')));
      }
    }
  }

  void _preview(Attachment image) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(image.note.split(' | ').first)),
      body: Center(child: InteractiveViewer(
        minScale: 0.5, maxScale: 8,
        child: Image.file(File(image.path),
          errorBuilder: (_, error, stack) => const Text('Image unavailable locally. Check attachment sync.')),
      )),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.archive['fields'] as Map? ?? {};
    final sides = widget.archive['sides'] as Map? ?? {};
    const labels = {
      'name': 'Company', 'person': 'Contact person', 'role': 'Job title',
      'department': 'Department', 'email': 'Primary email',
      'otherEmails': 'Other emails', 'phone': 'Primary phone',
      'otherPhones': 'Other phones', 'websites': 'Websites',
      'address': 'Addresses', 'country': 'Country', 'booth': 'Booth',
      'hall': 'Hall', 'whatsapp': 'WhatsApp', 'wechat': 'WeChat',
      'fax': 'Fax', 'social': 'Social profiles', 'other': 'Other details',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Saved business card')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(fields['name'] as String? ?? 'Business card', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.share_outlined), label: const Text('Share card and text')),
          TextButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _transcript));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card text copied.')));
            }
          }, icon: const Icon(Icons.copy_outlined), label: const Text('Copy details')),
        ]),
        FutureBuilder<List<Attachment>>(
          future: _images,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Could not load card attachments. Reopen this screen to retry.');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Column(children: [for (final side in ['front', 'back'])
              if (sides.containsKey(side)) Builder(builder: (context) {
                final matches = snapshot.data!.where((image) => image.note == 'Business card $side | ${widget.archive['id']}');
                if (matches.isEmpty) return ListTile(title: Text('$side image'), subtitle: const Text('Attachment not available locally. Check sync.'));
                final image = matches.first;
                return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                  Text(side == 'front' ? 'FRONT' : 'BACK'),
                  const SizedBox(height: 8),
                  InkWell(onTap: () => _preview(image), child: SizedBox(height: 190, width: double.infinity,
                    child: Image.file(File(image.path), cacheWidth: 1000, fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => const Center(child: Text('Image unavailable locally. Check attachment sync.'))))),
                  const Text('Tap to zoom'),
                ])));
              }),
            ]);
          },
        ),
        if (widget.archive['back_blank'] == true) const ListTile(title: Text('Back confirmed blank / single-sided')),
        const Divider(),
        for (final entry in fields.entries)
          if (entry.value.toString().trim().isNotEmpty) ListTile(
            title: Text(labels[entry.key] ?? entry.key.toString()),
            subtitle: SelectableText(entry.value.toString()),
          ),
        const Divider(),
        Text('Original recognition output', style: Theme.of(context).textTheme.titleLarge),
        for (final reading in widget.archive['ai_readings'] as List? ?? []) ExpansionTile(
          title: Text('OpenAI / ${reading['target_language']}'),
          subtitle: Text('${reading['created_at']} / ${reading['model']}'),
          children: [
            for (final warning in reading['warnings'] as List? ?? []) ListTile(title: Text(warning.toString())),
            for (final side in ['front', 'back']) ListTile(
              title: Text(side), subtitle: SelectableText(
                'Original:\n${(reading['transcript'] as Map)[side] ?? ''}\n\nTranslation:\n${(reading['translation'] as Map)[side] ?? ''}'),
            ),
            for (final detail in reading['extra_details'] as List? ?? [])
              ListTile(title: Text(detail['label'] as String), subtitle: SelectableText(detail['value'] as String)),
          ],
        ),
        const Text('These are source readings, not verified facts. Reviewed fields above may differ.'),
        for (final side in sides.entries) ExpansionTile(
          title: Text('${side.key} / OCR source'),
          children: [for (final pass in ((side.value as Map)['passes'] as Map? ?? {}).entries)
            ListTile(title: Text(pass.key.toString()),
              subtitle: SelectableText((pass.value as Map)['text'] as String? ?? ''))],
        ),
      ]),
    );
  }
}
