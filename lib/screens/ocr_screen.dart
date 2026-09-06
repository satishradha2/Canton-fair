import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/business_card_capture.dart';
import '../data/supplier_profile.dart';
import '../data/camera_capture_service.dart';
import '../widgets/card_ai_panel.dart';
import 'card_crop_screen.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  BusinessCardCapture? _draft;
  bool _busy = true;
  String? _error;
  String _status = 'Opening local card draft...';
  static const _fields = <String, String>{
    ...SupplierProfile.companyFields,
    ...SupplierProfile.contactFields,
  };
  final _controllers = {
    for (final key in _fields.keys) key: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _populate() {
    for (final entry in _controllers.entries) {
      entry.value.text = _draft!.fields[entry.key] ?? '';
    }
  }

  Future<void> _open() async {
    try {
      final draft = await BusinessCardCapture.open();
      if (!mounted) return;
      _draft = draft;
      final side = draft.pendingSide;
      if (side != null) {
        // Recover only a picker operation previously started by this OCR draft.
        final lost = await ImagePicker().retrieveLostData();
        if (lost.files?.isNotEmpty == true) {
          await draft.keepImage(side, lost.files!.first.path);
          await draft.readSide(side);
        } else {
          draft.pendingSide = null;
          await draft.save();
          if (lost.exception != null) {
            _error = 'Interrupted capture could not be recovered. Existing draft images are preserved.';
          }
        }
      }
      if (mounted) setState(_populate);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the local draft. Nothing was overwritten. Close this screen and retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persistEdit(String key, String value) async {
    final draft = _draft!;
    draft.fields[key] = value;
    draft.edited.add(key);
    try {
      await draft.save();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Draft could not be saved. Check free storage before leaving.');
      }
    }
  }

  Future<void> _capture(String side, ImageSource source) async {
    if (_busy || _draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Capturing $side. Keep all four edges visible and avoid glare.';
    });
    final draft = _draft!;
    try {
      draft.pendingSide = side;
      await draft.save();
      Future<XFile?> pick() => ImagePicker().pickImage(source: source);
      final photo = source == ImageSource.camera
          ? await CameraCaptureService.capture(pick) : await pick();
      if (photo == null) {
        draft.pendingSide = null;
        await draft.save();
        return;
      }
      await draft.keepImage(side, photo.path);
      if (mounted && Platform.isAndroid) {
        final corrected = await Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => CardCropScreen(path: draft.imagePath(side)),
        ));
        if (corrected != null) await draft.useCrop(side, corrected);
      }
      if (mounted) setState(() => _status = 'Reading $side on-device...');
      await draft.readSide(side);
      if (mounted) setState(_populate);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Capture or reading failed. Any copied original remains in your local draft. Retry reading or capture again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reread(String side) async {
    if (_busy) return;
    setState(() { _busy = true; _status = 'Reading $side again...'; _error = null; });
    try {
      await _draft!.readSide(side);
      if (mounted) setState(_populate);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reread this image. Your original and manual edits are preserved.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop(String side) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _status = 'Adjusting card edges...'; });
    try {
      final path = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => CardCropScreen(path: _draft!.imagePath(side)),
      ));
      if (path != null) {
        await _draft!.useCrop(side, path);
        await _draft!.readSide(side);
        if (mounted) setState(_populate);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not crop the card. The original is preserved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useDetails() async {
    if (_busy || _draft == null || ModalRoute.of(context)?.isCurrent != true) return;
    final draft = _draft!;
    if (!draft.sides.containsKey('front') ||
        (!draft.sides.containsKey('back') && !draft.backBlank)) {
      setState(() => _error = 'Capture the front and back, or confirm that the back is blank.');
      return;
    }
    if (_controllers['name']!.text.trim().isEmpty) {
      setState(() => _error = 'Enter or confirm the company / supplier name.');
      return;
    }
    setState(() { _busy = true; _status = 'Preserving reviewed details...'; });
    try {
      for (final entry in _controllers.entries) {
        draft.fields[entry.key] = entry.value.text.trim();
      }
      await draft.save();
      if (mounted) Navigator.of(context).pop<BusinessCardCapture>(draft);
    } catch (_) {
      if (mounted) {
        setState(() { _busy = false; _error = 'Could not save your draft. Please retry.'; });
      }
    }
  }

  void _preview(String side) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: Text('Business card - $side')),
      body: Center(child: InteractiveViewer(
        minScale: 0.5, maxScale: 8,
        child: Image.file(File(_draft!.imagePath(side)),
          errorBuilder: (_, error, stack) => const Text('Image unavailable on this device.')),
      )),
    )));
  }

  Widget _sidePanel(String side) {
    final draft = _draft!;
    final page = draft.sides[side];
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(side == 'front' ? '01 / FRONT' : '02 / BACK', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (page != null) ...[
          InkWell(onTap: _busy ? null : () => _preview(side), child: SizedBox(
            height: 170, width: double.infinity,
            child: Image.file(File(draft.imagePath(side)), fit: BoxFit.contain,
              cacheWidth: 1000,
              errorBuilder: (_, error, stack) => const Center(child: Text('Original unavailable. Capture again.'))),
          )),
          const Text('Tap the original to zoom. Retaking does not erase manual edits.'),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: _busy ? null : () => _capture(side, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: Text(page == null ? 'Capture $side' : 'Retake $side')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _capture(side, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Import image')),
          if (page != null) TextButton(onPressed: _busy ? null : () => _reread(side), child: const Text('Read again')),
          if (page != null && Platform.isAndroid) TextButton(onPressed: _busy ? null : () => _crop(side), child: const Text('Adjust crop')),
        ]),
        if (page?['processed_file'] != null) const Text('A perspective-corrected copy is used for reading. The preview above is the preserved original.'),
        if (side == 'back' && page == null) CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('The back is blank / this is a single-sided card'),
          value: draft.backBlank,
          onChanged: _busy ? null : (value) async {
            setState(() => draft.backBlank = value ?? false);
            try { await draft.save(); } catch (_) {
              if (mounted) setState(() => _error = 'Could not save the draft. Please retry.');
            }
          },
        ),
        for (final warning in (page?['warnings'] as List? ?? []))
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning.toString())),
        if (page != null) ExpansionTile(
          tilePadding: EdgeInsets.zero, title: const Text('Source text / recognition passes'),
          children: [for (final entry in (page['passes'] as Map? ?? {}).entries)
            ListTile(title: Text(entry.key.toString()),
              subtitle: SelectableText((entry.value as Map)['text'] as String? ?? ''))],
        ),
      ]),
    ));
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final candidates = draft?.candidates ?? <String, List<String>>{};
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Business card capture')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Keep the complete card', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Capture both sides, review details, then save to a supplier. Originals and recognition output are retained. Local drafts resume when you reopen this screen.'),
          const SizedBox(height: 12),
          if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8), Text(_status)],
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          if (draft != null) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: draft.mode, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reading scripts'),
              items: BusinessCardCapture.modes.map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
              onChanged: _busy ? null : (value) async {
                if (value == null) return;
                setState(() => draft.mode = value);
                try { await draft.save(); } catch (_) {
                  if (mounted) setState(() => _error = 'Could not save the reading preference.');
                }
              },
            ),
            const SizedBox(height: 8),
            const Text('After changing scripts, use Read again for each side. Arabic and other unsupported scripts require manual transcription. OCR suggestions are not verified facts.'),
            const SizedBox(height: 12),
            _sidePanel('front'), _sidePanel('back'),
            CardAiPanel(
              draft: draft, enabled: !_busy,
              onBusyChanged: (value) {
                if (mounted) setState(() { _busy = value; _status = 'Reading with OpenAI...'; });
              },
              onChanged: () { if (mounted) setState(_populate); },
            ),
            const SizedBox(height: 20),
            Text('Review contact details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Select alternative readings below a field or edit manually. Additional numbers, addresses and unmapped text are preserved with the card.'),
            const SizedBox(height: 16),
            for (final entry in _fields.entries) ...[
              TextField(
                controller: _controllers[entry.key], enabled: !_busy,
                minLines: 1,
                maxLines: SupplierProfile.multiline.contains(entry.key) ? 4 : 1,
                decoration: InputDecoration(labelText: entry.value,
                  helperText: draft.edited.contains(entry.key) ? 'Manually reviewed / edited' : null),
                onChanged: (value) => _persistEdit(entry.key, value),
              ),
              if ((candidates[entry.key]?.length ?? 0) > 1)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final value in candidates[entry.key]!) ActionChip(
                    label: Text(value), onPressed: _busy ? null : () {
                      _controllers[entry.key]!.text = value;
                      _persistEdit(entry.key, value);
                    },
                  ),
                ]),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(onPressed: _busy ? null : _useDetails,
              icon: const Icon(Icons.fact_check_outlined), label: const Text('Continue to supplier capture')),
            const SizedBox(height: 10),
            const Text('This step saves a local draft, not a supplier. Complete supplier capture to link the card images and details to your records. OCR is processed on-device; saved records follow your existing workspace sync settings.'),
          ],
        ])),
      ),
    );
  }
}
