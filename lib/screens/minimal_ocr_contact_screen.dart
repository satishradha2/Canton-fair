import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../data/business_card_parser.dart';
import '../data/database.dart';
import '../data/fair_capture_service.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';
import 'supplier_contacts_screen.dart';

class MinimalOcrContactScreen extends StatefulWidget {
  const MinimalOcrContactScreen({super.key, required this.fair});
  final Trip fair;
  @override
  State<MinimalOcrContactScreen> createState() => _MinimalOcrContactScreenState();
}

class _MinimalOcrContactScreenState extends State<MinimalOcrContactScreen> {
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
  bool _extracting = false;
  bool _saving = false;
  late final Future<String> _scope;

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

  Future<void> _capture(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 88);
    if (image == null || !mounted) return;
    setState(() { _image = image; _extracting = true; });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
      final values = BusinessCardParser.candidates(result.text);
      void apply(TextEditingController c, String key) { final value = values[key]; if (value != null && value.isNotEmpty) c.text = value.first; }
      apply(_company, 'name'); apply(_contact, 'person'); apply(_role, 'role'); apply(_phone, 'phone');
      apply(_email, 'email'); apply(_website, 'websites'); apply(_address, 'address'); apply(_country, 'country');
      _rawText.text = result.text;
    } catch (error) {
      if (mounted) _message('Could not read that card: $error');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
          designation: _role.text.trim(), phone: _phone.text.trim(), email: _email.text.trim()),
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
      if (_image != null) ...[ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: 1.7, child: Image.file(File(_image!.path), fit: BoxFit.cover))), const SizedBox(height: 12)],
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _extracting ? null : () => _capture(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera'))), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: _extracting ? null : () => _capture(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')))]),
      if (_extracting) const Padding(padding: EdgeInsets.only(top: 18), child: LinearProgressIndicator()), const SizedBox(height: 24),
      _field(_company, 'Supplier / company', required: true), _field(_contact, 'Contact person'), _field(_role, 'Role or designation'), _field(_phone, 'Phone', keyboard: TextInputType.phone), _field(_email, 'Email', keyboard: TextInputType.emailAddress), _field(_website, 'Website', keyboard: TextInputType.url), _field(_address, 'Address', lines: 2), _field(_country, 'Country / region'),
      if (_rawText.text.isNotEmpty) ExpansionTile(title: const Text('OCR source text'), children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(_rawText.text))]),
      const SizedBox(height: 24), FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save contact')),
    ]))),
  );

  Widget _field(TextEditingController controller, String label, {bool required = false, int lines = 1, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(controller: controller, maxLines: lines, keyboardType: keyboard, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), validator: required ? (value) => value == null || value.trim().isEmpty ? 'Enter the supplier or company name.' : null : null),
  );
}

class _CompanyChoice {
  const _CompanyChoice(this.company);
  final Exhibitor? company;
}
