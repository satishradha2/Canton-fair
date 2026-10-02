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
import '../widgets/field_workspace.dart';
import '../widgets/record_search.dart';

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
  int _step = 0;

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
      final transcriptForReview = result['transcript'] as Map?;
      final reviewSource = ['front', 'back'].map((side) =>
        (transcriptForReview?[side] ?? _sideText[side] ?? '').toString()).join('\n\n');
      final sourceCandidates = BusinessCardParser.candidates(reviewSource);
      final addressSuggestion = (fields['address'] ?? '').toString().trim();
      final fullAddresses = sourceCandidates['address'] ?? <String>[];
      String normalized(String value) => value.toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ').trim();
      final matchingAddresses = fullAddresses.where((address) =>
        addressSuggestion.isNotEmpty && normalized(address).contains(normalized(addressSuggestion))).toList();
      if (addressSuggestion.isEmpty && fullAddresses.length == 1) {
        fields['address'] = fullAddresses.single;
      } else if (matchingAddresses.length == 1) {
        fields['address'] = matchingAddresses.single;
      }
      if ((fields['country'] ?? '').toString().trim().isEmpty &&
          (sourceCandidates['country'] ?? []).length == 1) {
        fields['country'] = sourceCandidates['country']!.single;
      }
      final controllers = {'name': _company, 'person': _contact, 'role': _role, 'phone': _phone,
        'email': _email, 'websites': _website, 'address': _address, 'country': _country};
      const labels = {'name': 'Supplier / company', 'person': 'Contact person', 'role': 'Role',
        'phone': 'Phone', 'email': 'Email', 'websites': 'Website', 'address': 'Address', 'country': 'Country / region'};
      final accepted = <String>{for (final key in controllers.keys)
        if ((fields[key] ?? '').toString().trim().isNotEmpty && controllers[key]!.text.trim().isEmpty) key};
      final apply = await showDialog<bool>(context: context, barrierDismissible: false, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Review AI suggestions'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Select the values to apply. Existing entries are kept unless you select their replacement. Address lines are kept together. Country may be suggested from the address city; confirm it before saving.'),
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
    final ordered = [...exact, ...similar,
      ...companies.where((company) => !exact.contains(company) && !similar.contains(company))];
    if (!mounted) return null;
    if (companies.isEmpty) return const _CompanyChoice(null);
    var query = '';
    return showDialog<_CompanyChoice>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) {
        final matches = ordered.where((company) =>
          recordMatches(query, [company.name, company.country, company.category])).toList();
        return AlertDialog(
          title: Text(exact.isNotEmpty ? 'Existing company found' : 'Choose company or create new'),
          content: SizedBox(width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.48,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Matching companies appear first. Search all saved companies before creating another.'),
              const SizedBox(height: 12),
              RecordSearchField(hint: 'Search company, country or category',
                onChanged: (value) => update(() => query = value)),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${matches.length} of ${companies.length} companies')),
              Expanded(child: matches.isEmpty
                ? const Center(child: Text('No matches. Change your search or create a new company.'))
                : ListView.builder(itemCount: matches.length, itemBuilder: (_, index) {
                    final company = matches[index];
                    return ListTile(contentPadding: EdgeInsets.zero,
                      leading: Icon(exact.contains(company) ? Icons.verified_outlined : Icons.business_outlined),
                      title: Text(company.name),
                      subtitle: Text([
                        if (exact.contains(company)) 'Exact company match',
                        if (company.country.isNotEmpty) company.country,
                        if (company.category.isNotEmpty) company.category,
                      ].join(' | ')),
                      onTap: () => Navigator.of(context).pop(_CompanyChoice(company)));
                  })),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            if (exact.isEmpty) TextButton(
              onPressed: () => Navigator.of(context).pop(const _CompanyChoice(null)),
              child: const Text('Create new company')),
          ],
        );
      }),
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
          SearchableSelectionField<String>(
            value: hall,
            decoration: const InputDecoration(labelText: 'Hall number', border: OutlineInputBorder()),
            options: halls, labelFor: (name) => name,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _saving || _extracting;
    final reduced = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan business card')),
      bottomNavigationBar: SafeArea(top: false, child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
        child: Row(children: [
          if (_step > 0) ...[
            OutlinedButton(onPressed: busy ? null : () => _goStep(_step - 1),
              child: const Text('Back')),
            const SizedBox(width: 12),
          ],
          Expanded(child: FilledButton.icon(
            onPressed: busy ? null : () {
              if (_step < 2) {
                _goStep(_step + 1);
              } else if (_company.text.trim().isEmpty) {
                _goStep(1);
                _message('Enter the supplier or company name.');
              } else {
                _save();
              }
            },
            icon: _saving ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_step == 2 ? Icons.save_outlined : Icons.arrow_forward_rounded),
            label: Text(_saving ? 'Saving...' : _step == 0
                ? 'Review details' : _step == 1 ? 'Review & save' : 'Save contact'))),
        ]),
      )),
      body: SafeArea(bottom: false, child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(children: [
              for (var index = 0; index < 3; index++) Expanded(
                child: Padding(padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                  child: ChoiceChip(
                    label: Text(['1 Capture', '2 Details', '3 Review'][index]),
                    selected: _step == index,
                    onSelected: busy ? null : (_) => _goStep(index)))),
            ])),
          Expanded(child: Form(key: _formKey, child: AnimatedSwitcher(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            child: ListView(key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              FieldWorkspaceHeader(
                eyebrow: widget.fair.name,
                title: ['Capture the card', 'Confirm the details', 'Ready for your team'][_step],
                subtitle: ['Add the front and optional back. You can also continue with manual entry.',
                  'Check the extracted information. Nothing is saved until you confirm.',
                  'Review this contact before saving it under its company.'][_step],
                icon: [Icons.document_scanner_outlined, Icons.edit_note_outlined,
                  Icons.fact_check_outlined][_step]),
              const SizedBox(height: 18),
              if (_step == 0) ...[
                LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 600
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _cardSide(false)), const SizedBox(width: 12),
                      Expanded(child: _cardSide(true))])
                  : Column(children: [_cardSide(false), const SizedBox(height: 12), _cardSide(true)])),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _image == null || busy ? null : _extractAi,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(_backImage == null ? 'Read front with AI' : 'Read both sides with AI')),
                const SizedBox(height: 10),
                Text('Offline OCR runs after capture. AI provides additional suggestions for your review.',
                  style: theme.textTheme.bodySmall),
                if (_extracting) ...[
                  const SizedBox(height: 16), const LinearProgressIndicator(),
                  const SizedBox(height: 8), Text(_captureStatus),
                ],
                if (_aiResult != null) const Padding(padding: EdgeInsets.only(top: 12),
                  child: Text('AI reading ready. Continue to Details to confirm the fields.')),
              ],
              if (_step == 1) ...[
                FieldWorkspaceSection(title: 'Company identity', icon: Icons.business_outlined,
                  child: Column(children: [
                    _field(_company, 'Supplier / company', required: true),
                    _field(_website, 'Website', keyboard: TextInputType.url),
                  ])),
                const SizedBox(height: 14),
                FieldWorkspaceSection(title: 'Contact person', icon: Icons.person_outline,
                  child: Column(children: [
                    _field(_contact, 'Contact person'), _field(_role, 'Role or designation'),
                    _field(_phone, 'Phone', keyboard: TextInputType.phone),
                    _field(_email, 'Email', keyboard: TextInputType.emailAddress),
                  ])),
                const SizedBox(height: 14),
                FieldWorkspaceSection(title: 'Address & location', icon: Icons.location_on_outlined,
                  subtitle: 'Keep every address line. Confirm any country suggested from the city.',
                  child: Column(children: [
                    _field(_address, 'Full address', lines: 4), _field(_country, 'Country / region'),
                  ])),
              ],
              if (_step == 2) ...[
                FieldWorkspaceSection(title: 'Company & contact summary', icon: Icons.fact_check_outlined,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final entry in {
                      'Company': _company.text, 'Contact': _contact.text,
                      'Role': _role.text, 'Phone': _phone.text, 'Email': _email.text,
                      'Website': _website.text, 'Address': _address.text, 'Country': _country.text,
                    }.entries) Padding(padding: const EdgeInsets.only(bottom: 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.key, style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        SelectableText(entry.value.trim().isEmpty ? 'Not provided' : entry.value,
                          style: theme.textTheme.bodyMedium),
                      ])),
                    OutlinedButton.icon(onPressed: busy ? null : () => _goStep(1),
                      icon: const Icon(Icons.edit_outlined), label: const Text('Edit details')),
                  ])),
                const SizedBox(height: 14),
                const FieldWorkspaceSection(title: 'What happens next', icon: Icons.account_tree_outlined,
                  child: Text('You will select the company match and required categories. Hall and booth are requested when this company is first captured for the selected fair.')),
              ],
              if (_step > 0 && _rawText.text.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Card(child: ExpansionTile(title: const Text('Compare with OCR source'),
                  leading: const Icon(Icons.text_snippet_outlined),
                  children: [Padding(padding: const EdgeInsets.all(18),
                    child: SelectableText(_rawText.text))]))),
              if (_step > 0 && _aiResult != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Card(child: ExpansionTile(title: const Text('Additional AI reading'),
                  children: [Padding(padding: const EdgeInsets.all(18),
                    child: SelectableText(const JsonEncoder.withIndent('  ').convert(_aiResult)))]))),
            ]),
          ))),
        ]),
      ))),
    );
  }

  void _goStep(int next) {
    if (_saving || _extracting || next == _step) return;
    if (next == 2 && _company.text.trim().isEmpty) {
      if (_step == 1) _formKey.currentState?.validate();
      _message('Enter the supplier or company name before review.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = next);
  }
  Widget _field(TextEditingController controller, String label, {bool required = false, int lines = 1, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(controller: controller, enabled: !_extracting && !_saving, maxLines: lines, keyboardType: keyboard, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), validator: required ? (value) => value == null || value.trim().isEmpty ? 'Enter the supplier or company name.' : null : null),
  );
}

class _CompanyChoice {
  const _CompanyChoice(this.company);
  final Exhibitor? company;
}
