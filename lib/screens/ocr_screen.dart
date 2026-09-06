import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/business_card_capture.dart';
import '../data/supplier_profile.dart';
import '../data/camera_capture_service.dart';
import '../widgets/card_ai_panel.dart';
import 'card_crop_screen.dart';
import 'supplier_profile_screen.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  static const _images = MethodChannel('canton_fair_crm/card_image');
  static const _scanner = MethodChannel('canton_fair_crm/card_scanner');
  BusinessCardCapture? _draft;
  bool _busy = true;
  String? _error;
  String? _cropNotice;
  String _status = 'Opening local card draft...';
  static const _primaryFields = {'name', 'person', 'role', 'email', 'phone'};
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
        String? recovered;
        if (Platform.isAndroid) {
          recovered = await _scanner.invokeMethod<String>('recover', {'token': '${draft.id}_$side'});
        }
        if (recovered != null) {
          await draft.keepImage(side, recovered);
          draft.sides[side]!['capture_method'] = 'live_scanner';
          await draft.save();
          await _scanner.invokeMethod<void>('discard', {'token': '${draft.id}_$side'});
          await draft.readSide(side);
        } else {
        // Recover only a picker operation previously started by this OCR draft.
        final lost = await ImagePicker().retrieveLostData();
        if (lost.files?.isNotEmpty == true) {
          await draft.keepImage(side, lost.files!.first.path);
          await _autoCrop(draft, side);
          await draft.readSide(side);
        } else {
          draft.pendingSide = null;
          await draft.save();
          if (lost.exception != null) {
            _error = 'Interrupted capture could not be recovered. Existing draft images are preserved.';
          }
        }
        }
      }
      if (draft.applyLatestAi() > 0) await draft.save();
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
      _cropNotice = null;
      _status = 'Capturing $side. Keep all four edges visible and avoid glare.';
    });
    final draft = _draft!;
    try {
      draft.pendingSide = side;
      await draft.save();
      if (Platform.isAndroid && source == ImageSource.camera) {
        if (mounted) setState(() => _status = 'Opening live card scanner. Review the detected edges before accepting.');
        final token = '${draft.id}_$side';
        final scan = await CameraCaptureService.capture(() =>
            _scanner.invokeMethod<String>('scan', {'token': token}));
        if (scan == null) {
          draft.pendingSide = null;
          await draft.save();
          return;
        }
        await draft.keepImage(side, scan);
        draft.sides[side]!['capture_method'] = 'live_scanner';
        await draft.save();
        await _scanner.invokeMethod<void>('discard', {'token': token});
        if (mounted) setState(() => _status = 'Reading the accepted $side card scan...');
        await draft.readSide(side);
        if (mounted) setState(_populate);
        return;
      }
      Future<XFile?> pick() => ImagePicker().pickImage(source: source);
      final photo = source == ImageSource.camera
          ? await CameraCaptureService.capture(pick) : await pick();
      if (photo == null) {
        draft.pendingSide = null;
        await draft.save();
        return;
      }
      await draft.keepImage(side, photo.path);
      await _autoCrop(draft, side);
      if (mounted) setState(() => _status = 'Reading $side on-device...');
      await draft.readSide(side);
      if (mounted) setState(_populate);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Live card scanning is unavailable. Existing images are unchanged.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Capture or reading failed. Any copied original remains in your local draft. Retry reading or capture again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _autoCrop(BusinessCardCapture draft, String side) async {
    if (!Platform.isAndroid) return;
    if (mounted) setState(() => _status = 'Automatically cropping $side...');
    try {
      final prepared = await _images.invokeMapMethod<String, dynamic>(
        'prepare', {'path': draft.imagePath(side)},
      ).timeout(const Duration(seconds: 20));
      if (prepared == null || prepared['detected'] != true) {
        if (mounted) {
          setState(() => _cropNotice =
              'Could not confidently detect the $side edges. Reading the original instead. Adjust crop is optional.');
        }
        return;
      }
      final corrected = await _images.invokeMethod<String>('crop', {
        'path': prepared['path'], 'corners': prepared['corners'],
      }).timeout(const Duration(seconds: 20));
      if (corrected == null) throw StateError('No corrected image returned.');
      await draft.useCrop(side, corrected);
    } catch (_) {
      if (mounted) {
        setState(() => _cropNotice =
            'Automatic crop was unavailable for the $side. Reading the preserved original instead. You can optionally adjust the crop later.');
      }
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

  Future<void> _useDetails({bool existing = false}) async {
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
    final destination = existing ? await chooseCardSupplier(context, allowCreate: false) : -1;
    if (!mounted || destination == null) return;
    draft.supplierDestination = destination;
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
        Text(side == 'front' ? 'Front of card' : 'Back of card', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (page != null) ...[
          InkWell(onTap: _busy ? null : () => _preview(side), child: SizedBox(
            height: 130, width: double.infinity,
            child: Image.file(File(draft.imagePath(side)), fit: BoxFit.contain,
              cacheWidth: 1000,
              errorBuilder: (_, error, stack) => const Center(child: Text('Original unavailable. Capture again.'))),
          )),
          const Text('Tap image to enlarge.'),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: _busy ? null : () => _capture(side, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: Text(page == null ? 'Capture $side' : 'Retake $side')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _capture(side, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Import image')),
        ]),
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
        if (page != null) ExpansionTile(
          tilePadding: EdgeInsets.zero, title: const Text('Scan options and reading notes'),
          children: [
            Wrap(spacing: 8, children: [
              TextButton(onPressed: _busy ? null : () => _reread(side), child: const Text('Read again')),
              if (Platform.isAndroid) TextButton(onPressed: _busy ? null : () => _crop(side), child: const Text('Adjust crop')),
            ]),
            if (page['processed_file'] != null) ListTile(subtitle: Text(page['crop_verified'] == true
                ? 'The corrected copy is used for reading.' : 'The original is used because crop verification was inconclusive.')),
            for (final warning in (page['warnings'] as List? ?? []))
              ListTile(subtitle: Text(side == 'back' && warning.toString().startsWith('Very little text detected.')
                  ? 'Little text detected. A logo-only back is fine; the image is retained.' : warning.toString())),
            for (final entry in (page['passes'] as Map? ?? {}).entries)
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

  Widget _fieldEditor(MapEntry<String, String> entry, Map<String, List<String>> candidates) {
    final draft = _draft!;
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _controllers[entry.key], enabled: !_busy,
          minLines: 1, maxLines: SupplierProfile.multiline.contains(entry.key) ? 4 : 1,
          decoration: InputDecoration(labelText: entry.value,
            helperText: draft.edited.contains(entry.key) ? 'Manually reviewed / edited' : null),
          onChanged: (value) => _persistEdit(entry.key, value)),
        if ((candidates[entry.key]?.length ?? 0) > 1)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final value in candidates[entry.key]!) ActionChip(label: Text(value),
              onPressed: _busy ? null : () {
                _controllers[entry.key]!.text = value;
                _persistEdit(entry.key, value);
              }),
          ]),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final candidates = draft?.candidates ?? <String, List<String>>{};
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Scan business card')),
        bottomNavigationBar: draft == null ? null : SafeArea(top: false,
          child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Review before saving', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton.icon(onPressed: _busy ? null : () => _useDetails(),
                icon: const Icon(Icons.add_business_outlined), label: const Text('Save new supplier')),
              OutlinedButton(onPressed: _busy ? null : () => _useDetails(existing: true),
                child: const Text('Update existing supplier')),
            ]),
          ]))),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Card to supplier', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Scan. Review. Save.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8), Text(_status)],
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          if (_cropNotice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_cropNotice!))),
          if (draft != null) ...[
            const SizedBox(height: 16),
            Card(child: ExpansionTile(
              key: const PageStorageKey('card-images'),
              initiallyExpanded: draft.sides.isEmpty,
              leading: const Icon(Icons.contact_page_outlined),
              title: const Text('Business card images'),
              subtitle: Text('${draft.sides.length} of 2 sides captured${draft.backBlank ? ' - single-sided card' : ''}'),
              children: [_sidePanel('front'), _sidePanel('back')],
            )),
            const SizedBox(height: 8),
            CardAiPanel(
              key: ValueKey('card-ai-${draft.id}'),
              draft: draft, enabled: !_busy,
              onBusyChanged: (value) {
                if (mounted) setState(() { _busy = value; _status = 'Reading with OpenAI...'; });
              },
              onChanged: () { if (mounted) setState(_populate); },
            ),
            const SizedBox(height: 24),
            Text('Supplier details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Check the extracted details. All fields are editable.',
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final key in _primaryFields)
              _fieldEditor(MapEntry(key, _fields[key]!), candidates),
            Card(child: ExpansionTile(
              key: const PageStorageKey('supplier-extra-fields'),
              title: const Text('More supplier details'),
              subtitle: const Text('Address, website, messaging and company information'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                for (final entry in _fields.entries)
                  if (!_primaryFields.contains(entry.key)) _fieldEditor(entry, candidates),
              ],
            )),
            const SizedBox(height: 8),
            ExpansionTile(title: const Text('On-device reading settings'),
              childrenPadding: const EdgeInsets.symmetric(vertical: 12), children: [
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
            const Text('After changing scripts, choose Read again under each image. Use AI for additional languages; review all results before saving.'),
            ]),
            const SizedBox(height: 10),
            Text('Draft saved on this device. Supplier records are saved after confirmation.',
              style: Theme.of(context).textTheme.bodySmall),
          ],
        ])),
      ),
    );
  }
}
