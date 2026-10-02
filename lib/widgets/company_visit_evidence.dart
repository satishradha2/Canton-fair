import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/approval_policy.dart';
import '../data/database.dart';
import '../data/product_capture_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import '../screens/supplier_voice_note_screen.dart';
import '../screens/visit_audio_player_screen.dart';

class CompanyVisitEvidence extends StatefulWidget {
  const CompanyVisitEvidence({super.key, required this.scope, required this.company,
    required this.visitKey, required this.section, required this.canEdit});
  final String scope, visitKey, section;
  final Exhibitor company;
  final bool canEdit;
  @override
  State<CompanyVisitEvidence> createState() => _CompanyVisitEvidenceState();
}
class _CompanyVisitEvidenceState extends State<CompanyVisitEvidence> {
  late Future<List<Attachment>> _items;
  bool _busy = false;
  String get _context => 'Visit ${widget.visitKey} / ${widget.section}';
  @override
  void initState() { super.initState(); _items = _load(); }
  Future<List<Attachment>> _load() async {
    await ProductCaptureService.checkScope(widget.scope);
    final items = await TradeDatabase.instance.getAttachments('exhibitor', widget.company.id!);
    return items.where((item) {
      try { final data = ApprovalPolicy.jsonObject(item.note);
        return data['context'] == _context || (data['visit_key'] == widget.visitKey && data['section'] == widget.section);
      } catch (_) { return false; }
    }).toList();
  }
  Future<void> _capture({bool audio = false, bool camera = false}) async {
    setState(() => _busy = true);
    try {
      await ProductCaptureService.checkScope(widget.scope);
      if (!await ProductCaptureService.canWrite()) throw StateError('Read-only account.');
      if (!mounted) return;
      if (audio) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierVoiceNoteScreen(supplier: widget.company, contextLabel: _context, expectedScope: widget.scope)));
      } else {
        final picker = ImagePicker();
        final images = camera ? [await picker.pickImage(source: ImageSource.camera)].whereType<XFile>().toList() : await picker.pickMultiImage();
        await TeamWorkspaceService.exclusive(() async {
          await ProductCaptureService.checkScope(widget.scope);
          if (!await ProductCaptureService.canWrite()) throw StateError('Read-only account.');
          final root = await getApplicationDocumentsDirectory();
          final folder = Directory('${root.path}/attachments/${widget.scope}/visits/${widget.visitKey}');
          await folder.create(recursive: true);
          for (final image in images) {
            final path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_${image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
            await File(image.path).copy(path);
            await TradeDatabase.instance.insert('attachments', {'owner_type': 'exhibitor', 'owner_id': widget.company.id!, 'kind': 'image', 'path': path,
              'note': jsonEncode({'visit_key': widget.visitKey, 'section': widget.section, 'label': image.name})});
          }
        });
      }
      if (mounted) setState(() => _items = _load());
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture evidence: $error'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(Attachment item) async {
    try {
      await ProductCaptureService.checkScope(widget.scope);
      if (!mounted) return;
      if (item.kind == 'audio') {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisitAudioPlayerScreen(scope: widget.scope, path: item.path, supplierName: widget.company.name, transcript: '', report: '')));
      } else {
        await showDialog<void>(context: context, builder: (context) => Dialog(child: InteractiveViewer(child: Image.file(File(item.path), errorBuilder: (_, error, stack) => const Padding(padding: EdgeInsets.all(24), child: Text('Image unavailable. Try Sync.'))))));
      }
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (widget.canEdit) Wrap(spacing: 8, children: [
      TextButton.icon(onPressed: _busy ? null : () => _capture(audio: true), icon: const Icon(Icons.mic_none), label: const Text('Add voice note')),
      TextButton.icon(onPressed: _busy ? null : () => _capture(camera: true), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo')),
      TextButton.icon(onPressed: _busy ? null : () => _capture(), icon: const Icon(Icons.photo_library_outlined), label: const Text('Add images / documents')),
    ]),
    const Text('Documents and certificates can be captured as photos. Recordings stay in this section.'),
    FutureBuilder<List<Attachment>>(future: _items, builder: (context, snapshot) {
      if (snapshot.hasError) return Text('Could not load evidence: ${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return Column(children: [for (final item in snapshot.data!) ListTile(
        leading: Icon(item.kind == 'audio' ? Icons.graphic_eq : Icons.image_outlined),
        title: Text(item.kind == 'audio' ? 'Voice note - ${widget.section}' : 'Photo / document - ${widget.section}'),
        subtitle: Text('${item.createdAt}'), onTap: () => _open(item),
        trailing: IconButton(tooltip: 'Share evidence', icon: const Icon(Icons.share_outlined),
          onPressed: () async { await ProductCaptureService.checkScope(widget.scope); await SharePlus.instance.share(ShareParams(files: [XFile(item.path)])); }),
      )]);
    }),
  ]);
}
