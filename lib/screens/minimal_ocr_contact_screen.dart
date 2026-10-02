import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/business_card_parser.dart';
import '../data/card_ai_service.dart';
import '../data/camera_capture_service.dart';
import '../data/database.dart';
import '../data/fair_capture_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import 'supplier_contacts_screen.dart';
import '../widgets/animated_card_preview.dart';

class MinimalOcrContactScreen extends StatefulWidget {
  const MinimalOcrContactScreen({super.key, required this.fair});
  final Trip fair;
  @override
  State<MinimalOcrContactScreen> createState() => _MinimalOcrContactScreenState();
}

class _MinimalOcrContactScreenState extends State<MinimalOcrContactScreen> {
  static const _scanner = MethodChannel('canton_fair_crm/card_scanner');
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _role = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _country = TextEditingController();
  final _rawText = TextEditingController();
  XFile? _image;
  XFile? _backImage;
  final _sideText = <String, String>{};
  bool _extracting = false;
  bool _saving = false;
  late final Future<String> _scope;
  Map<String, dynamic>? _aiResult;
  String _captureStatus = '';
  String? _readingSide;
  bool _aiProcessing = false;

  @override
  void initState() {
    super.initState();
    _scope = TeamWorkspaceService().scopeKey();
  }

  @override
  void dispose() {
    for (final controller in [_company, _contact, _role, _phone, _email, _website, _address, _country, _rawText]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _capture(ImageSource source, {bool back = false}) async {
    if (_extracting || _saving) return;
    final side = back ? 'back' : 'front';
    setState(() { _extracting = true; _captureStatus = source == ImageSource.camera && Platform.isAndroid
      ? 'Opening auto scanner. Keep all four card edges visible, then review the crop.' : 'Selecting $side image...'; });
    try {
      final scope = await _scope;
      if (scope != await TeamWorkspaceService().scopeKey()) throw StateError('Workspace changed. Reopen the scanner.');
      XFile? image;
      if (source == ImageSource.camera && Platform.isAndroid) {
        final token = 'card_${DateTime.now().microsecondsSinceEpoch}_$side';
        final scan = await CameraCaptureService.capture(() => _scanner.invokeMethod<String>('scan', {'token': token}));
        if (scan == null) return;
        if (scope != await TeamWorkspaceService().scopeKey()) throw StateError('Workspace changed. Reopen the scanner.');
        final root = await getApplicationDocumentsDirectory();
        final folder = Directory('${root.path}/attachments/$scope/business_card_scans');
        await folder.create(recursive: true);
        final retained = await File(scan).copy('${folder.path}/$token.jpg');
        image = XFile(retained.path);
        try { await _scanner.invokeMethod<void>('discard', {'token': token}); }
        catch (_) { /* The accepted crop has already been retained. */ }
      } else {
        Future<XFile?> pick() => _picker.pickImage(source: source, imageQuality: 88);
        image = source == ImageSource.camera ? await CameraCaptureService.capture(pick) : await pick();
      }
      if (image == null || !mounted) return;
      if (scope != await TeamWorkspaceService().scopeKey()) throw StateError('Workspace changed. Reopen the scanner.');
      if (!mounted) return;
      setState(() {
        if (back) { _backImage = image; } else { _image = image; }
        _sideText.remove(side); _refreshSourceText(); _aiResult = null;
        _captureStatus = 'Reading the accepted $side image...';
        _readingSide = side;
      });
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        if (!mounted) return;
        _sideText[side] = result.text;
        final values = BusinessCardParser.candidates(result.text);
        void apply(TextEditingController c, String key) { final value = values[key]; if (value != null && value.isNotEmpty && (!back || c.text.trim().isEmpty)) c.text = value.first; }
        apply(_company, 'name'); apply(_contact, 'person'); apply(_role, 'role'); apply(_phone, 'phone');
        apply(_email, 'email'); apply(_website, 'websites'); apply(_address, 'address'); apply(_country, 'country');
        _refreshSourceText();
      } finally { await recognizer.close(); }
    } on PlatformException catch (error) {
      if (mounted) _message(error.message ?? 'Auto scanning is unavailable. Check Google Play services and internet access for first-time setup, or use Gallery.');
    } catch (error) {
      if (mounted) _message('Could not read that card: $error');
    } finally {
      if (mounted) setState(() { _extracting = false; _captureStatus = ''; _readingSide = null; });
    }
  }

  void _refreshSourceText() {
    _rawText.text = ['front', 'back'].where((side) => (_sideText[side] ?? '').trim().isNotEmpty)
      .map((side) => '${side == 'front' ? 'FRONT' : 'BACK'}\n${_sideText[side]}').join('\n\n');
  }

  Widget _cardSide(bool back) {
    final image = back ? _backImage : _image;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(back ? 'Back (optional)' : 'Front', style: Theme.of(context).textTheme.titleMedium)),
        if (back && image != null) IconButton(tooltip: 'Remove back image', onPressed: _extracting || _saving ? null : () => setState(() {
          _backImage = null; _sideText.remove('back'); _aiResult = null; _refreshSourceText();
        }), icon: const Icon(Icons.close))]),
      const SizedBox(height: 8),
      AnimatedCardPreview(path: image?.path, back: back,
        processing: _extracting && (_aiProcessing || _readingSide == (back ? 'back' : 'front'))),
      if (back && image == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Optional: add the back if it contains more details.')),
      const SizedBox(height: 12),
      if (Platform.isAndroid) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Auto scan detects the card edges. Review or adjust the crop before accepting. Only the accepted card crop is used.')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _extracting || _saving ? null : () => _capture(ImageSource.camera, back: back), icon: const Icon(Icons.document_scanner_outlined), label: Text(image == null ? (Platform.isAndroid ? 'Auto scan' : 'Camera') : 'Retake')),
        OutlinedButton.icon(onPressed: _extracting || _saving ? null : () => _capture(ImageSource.gallery, back: back), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
      ]),
    ])));
  }

  Future<void> _extractAi() async {
    if (_image == null || _extracting || _saving) return;
    final consent = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Extract business card with AI?'),
      content: Text('This sends ${_backImage == null ? 'the front image' : 'both front and back images'} and OCR text through your configured Supabase service to OpenAI. Internet access is required and API usage may incur a charge. Review all suggestions before saving.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Extract with AI'))],
    ));
    if (consent != true || !mounted) return;
    setState(() { _extracting = true; _aiProcessing = true; _captureStatus = 'AI is reading the card images. Suggestions will be shown for your review.'; });
    try {
      final result = await CardAiService.readPhoto(scope: await _scope, path: _image!.path, text: _sideText['front'] ?? '',
        backPath: _backImage?.path, backText: _sideText['back'] ?? '');
      if (!mounted) return;
      setState(() { _aiProcessing = false; _captureStatus = 'Reading complete. Review the AI suggestions.'; });
      final fields = Map<String, dynamic>.from(result['fields'] as Map);
      final controllers = {'name': _company, 'person': _contact, 'role': _role, 'phone': _phone,
        'email': _email, 'websites': _website, 'address': _address, 'country': _country};
      const labels = {'name': 'Supplier / company', 'person': 'Contact person', 'role': 'Role',
        'phone': 'Phone', 'email': 'Email', 'websites': 'Website', 'address': 'Address', 'country': 'Country / region'};
      final accepted = <String>{for (final key in controllers.keys)
        if ((fields[key] ?? '').toString().trim().isNotEmpty && controllers[key]!.text.trim().isEmpty) key};
      final apply = await showDialog<bool>(context: context, barrierDismissible: false, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Review AI suggestions'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Select the values to apply. Existing entries are kept unless you select their replacement.'),
          for (final key in controllers.keys) if ((fields[key] ?? '').toString().trim().isNotEmpty) CheckboxListTile(
            contentPadding: EdgeInsets.zero, title: Text(labels[key]!), subtitle: Text('${fields[key]}${controllers[key]!.text.isEmpty ? '' : '\nCurrent: ${controllers[key]!.text}'}'), value: accepted.contains(key),
            onChanged: (value) => update(() { if (value == true) { accepted.add(key); } else { accepted.remove(key); } })),
          for (final warning in result['warnings'] as List? ?? []) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Review: $warning')),
        ]))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep current fields')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply selected suggestions'))],
      )));
      if (!mounted) return;
      setState(() {
        _aiResult = result;
        if (apply == true) {
          for (final key in accepted) { controllers[key]!.text = fields[key].toString(); }
          final transcript = result['transcript'] as Map?;
          if (transcript != null) {
            _rawText.text = ['front', 'back'].where((side) => (transcript[side] ?? '').toString().trim().isNotEmpty)
              .map((side) => '${side == 'front' ? 'FRONT' : 'BACK'}\n${transcript[side]}').join('\n\n');
          }
        }
      });
      _message('AI reading ready. Review company and contact details before saving.');
    } catch (error) { if (mounted) _message('AI extraction could not complete: $error. Offline OCR and manual entry remain available.'); }
    finally { if (mounted) setState(() { _extracting = false; _aiProcessing = false; _captureStatus = ''; }); }
  }

  Future<void> _save() async {
    if (_extracting || _saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final database = TradeDatabase.instance;
      final choice = await _chooseCompany(database);
      if (choice == null || !mounted) return;
      final existing = choice.company;
      final hasLocation = existing?.id != null && await FairCaptureService.hasLocation(existing!.id!, widget.fair.id!);
      (String, String)? location;
      if (!hasLocation) {
        final currentFair = await database.getTripById(widget.fair.id!);
        if (currentFair == null) throw StateError('This fair is no longer available.');
        if (!mounted) return;
        location = await _chooseLocation(currentFair);
        if (location == null) return;
      }
      final exhibitorId = await FairCaptureService.save(
        scope: await _scope, fair: widget.fair, company: existing ?? _newCompany(),
        contact: Contact(exhibitorId: existing?.id ?? 0,
          name: _contact.text.trim().isEmpty ? 'Primary contact' : _contact.text.trim(),
          designation: _role.text.trim(), phone: _phone.text.trim(), email: _email.text.trim(),
          profileJson: jsonEncode({'website': _website.text.trim(), 'address': _address.text.trim(),
            'country': _country.text.trim(), 'ocr_source': _rawText.text.trim(), 'ocr_sides': _sideText,
            if (_aiResult != null) 'ai_reading': _aiResult})),
        hall: location?.$1, booth: location?.$2,
      );
      if (mounted) {
        _message('Card linked to ${existing?.name ?? _company.text.trim()} at ${widget.fair.name}. Existing contacts are reused.');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SupplierContactsScreen(companyId: exhibitorId, fairId: widget.fair.id)));
      }
    } catch (error) {
      if (mounted) _message('Could not save contact: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Exhibitor _newCompany() => Exhibitor(
      tripId: widget.fair.id!,
      name: _company.text.trim(),
      booth: '',
      hall: '',
      category: '',
      country: _country.text.trim(),
      contactCompanyNotes: [
        if (_website.text.trim().isNotEmpty) 'Website: ${_website.text.trim()}',
        if (_address.text.trim().isNotEmpty) 'Address: ${_address.text.trim()}',
        if (_rawText.text.trim().isNotEmpty) 'OCR source:\n${_rawText.text.trim()}',
      ].join('\n\n'),
    );

  Future<_CompanyChoice?> _chooseCompany(TradeDatabase database) async {
    final target = _companyKey(_company.text);
    final companies = await database.getExhibitors(null);
    final exact = companies.where((company) => _companyKey(company.name) == target).toList();
    final similar = companies.where((company) {
      final key = _companyKey(company.name);
      return key != target && key.length > 4 && target.length > 4 && (key.contains(target) || target.contains(key));
    }).toList();
    final candidates = [...exact, ...similar];
    if (!mounted) return null;
    if (candidates.isEmpty) return const _CompanyChoice(null);
    return showDialog<_CompanyChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exact.isNotEmpty ? 'Existing company found' : 'Possible company match'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exact.isNotEmpty ? 'Save this card under the existing company, or create a separate record.' : 'Check whether this card belongs to an existing company.'),
            const SizedBox(height: 12),
            ...candidates.take(4).map((company) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.business_outlined),
              title: Text(company.name),
              subtitle: Text(company.country.isEmpty ? 'Existing supplier record' : company.country),
              onTap: () => Navigator.of(context).pop(_CompanyChoice(company)),
            )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          if (exact.isEmpty) TextButton(onPressed: () => Navigator.of(context).pop(const _CompanyChoice(null)), child: const Text('Create new company')),
        ],
      ),
    );
  }

  String _companyKey(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s.,&()\-]'), '');

  Future<(String, String)?> _chooseLocation(Trip fair) async {
    final halls = FairCaptureService.halls(fair);
    if (halls.isEmpty) {
      _message('Create halls for ${fair.name} in Masters, then save this card.');
      return null;
    }
    final form = GlobalKey<FormState>();
    final booth = TextEditingController();
    String? hall;
    final result = await showDialog<(String, String)>(
      context: context, barrierDismissible: false,
      builder: (context) => StatefulBuilder(builder: (context, setModalState) => AlertDialog(
        title: const Text('Company location at this fair'),
        content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fair.name), const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Hall number', border: OutlineInputBorder()),
            items: halls.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
            validator: (value) => value == null ? 'Select a hall.' : null,
            onChanged: (value) => setModalState(() => hall = value),
          ),
          if (hall != null) ...[
            const SizedBox(height: 16),
            TextFormField(controller: booth, decoration: const InputDecoration(labelText: 'Booth number', border: OutlineInputBorder()),
              validator: (value) => value == null || value.trim().isEmpty ? 'Enter the booth number.' : null),
          ],
          const SizedBox(height: 12),
          const Text('Later cards for this company at this fair will use the same hall and booth.'),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate() && hall != null && booth.text.trim().isNotEmpty) {
              Navigator.pop(context, (hall!, booth.text.trim()));
            }
          }, child: const Text('Save contact and location')),
        ],
      )),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), booth.dispose);
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan business card')),
    body: SafeArea(child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Capture and review', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text('Fair: ${widget.fair.name}'),
      const SizedBox(height: 6), const Text('Use a clear card image, then confirm the details before saving.'), const SizedBox(height: 20),
      _cardSide(false),
      const SizedBox(height: 12),
      _cardSide(true),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _image == null || _extracting || _saving ? null : _extractAi,
        icon: const Icon(Icons.auto_awesome_outlined), label: Text(_backImage == null ? 'Extract front with AI' : 'Extract front + back with AI')),
      const SizedBox(height: 8), const Text('Camera / Gallery runs offline OCR. Use AI to read the image and suggest structured contact details.'),
      if (_extracting) ...[const Padding(padding: EdgeInsets.only(top: 18), child: LinearProgressIndicator()),
        if (_captureStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_captureStatus))], const SizedBox(height: 24),
      _field(_company, 'Supplier / company', required: true), _field(_contact, 'Contact person'), _field(_role, 'Role or designation'), _field(_phone, 'Phone', keyboard: TextInputType.phone), _field(_email, 'Email', keyboard: TextInputType.emailAddress), _field(_website, 'Website', keyboard: TextInputType.url), _field(_address, 'Address', lines: 2), _field(_country, 'Country / region'),
      if (_rawText.text.isNotEmpty) ExpansionTile(title: const Text('OCR source text'), children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(_rawText.text))]),
      if (_aiResult != null) ExpansionTile(title: const Text('Complete AI reading and additional card details'), children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(const JsonEncoder.withIndent('  ').convert(_aiResult)))]),
      AnimatedSwitcher(duration: Duration(milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 300),
        child: _aiResult == null ? const SizedBox.shrink() : Container(key: const ValueKey('ai-ready'),
          margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100), borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [Icon(Icons.check_circle_outline), SizedBox(width: 12), Expanded(child: Text('AI reading ready. Confirm your contact details before saving.'))]))),
      const SizedBox(height: 24), FilledButton.icon(onPressed: _saving || _extracting ? null : _save, icon: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save contact')),
    ]))),
  );

  Widget _field(TextEditingController controller, String label, {bool required = false, int lines = 1, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(controller: controller, enabled: !_extracting && !_saving, maxLines: lines, keyboardType: keyboard, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), validator: required ? (value) => value == null || value.trim().isEmpty ? 'Enter the supplier or company name.' : null : null),
  );
}

class _CompanyChoice {
  const _CompanyChoice(this.company);
  final Exhibitor? company;
}
