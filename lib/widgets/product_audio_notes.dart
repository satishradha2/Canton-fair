import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/database.dart';
import '../models/models.dart';
import '../screens/supplier_voice_note_screen.dart';
import '../screens/visit_audio_player_screen.dart';

class ProductAudioNotes extends StatefulWidget {
  const ProductAudioNotes({super.key, required this.scope, required this.productId,
    required this.productName, required this.canEdit});
  final String scope;
  final int productId;
  final String productName;
  final bool canEdit;
  @override
  State<ProductAudioNotes> createState() => _ProductAudioNotesState();
}

class _ProductAudioNotesState extends State<ProductAudioNotes> {
  late Future<List<Attachment>> _notes;
  @override
  void initState() { super.initState(); _notes = _load(); }
  Future<List<Attachment>> _load() async =>
      (await TradeDatabase.instance.getAttachments('product', widget.productId)).where((item) => item.kind == 'audio').toList();
  Future<void> _record() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierVoiceNoteScreen(
      productId: widget.productId, productName: widget.productName, contextLabel: 'Product: ${widget.productName}',
    )));
    if (mounted) setState(() => _notes = _load());
  }
  String _label(Attachment note) {
    try {
      final data = ApprovalPolicy.jsonObject(note.note);
      return [data['notes'], data['recorded_at']].whereType<String>().where((value) => value.isNotEmpty).join('\n');
    } catch (_) { return note.note; }
  }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Voice notes for this product', style: Theme.of(context).textTheme.titleLarge),
      if (widget.canEdit) TextButton.icon(onPressed: _record, icon: const Icon(Icons.mic_none), label: const Text('Add another voice note')),
      FutureBuilder<List<Attachment>>(future: _notes, builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Could not load audio: ${snapshot.error}');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.isEmpty) return const Text('No voice notes saved for this product yet.');
        return Column(children: snapshot.data!.map((note) => ListTile(
          leading: const Icon(Icons.graphic_eq), title: Text(_label(note).isEmpty ? 'Product voice note' : _label(note)),
          trailing: const Icon(Icons.play_circle_outline), onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VisitAudioPlayerScreen(scope: widget.scope, path: note.path, supplierName: widget.productName, transcript: '', report: ''),
          )),
        )).toList());
      }),
    ],
  )));
}
