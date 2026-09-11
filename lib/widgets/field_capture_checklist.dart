import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/camera_capture_service.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class FieldCapturePhoto {
  const FieldCapturePhoto({required this.path, required this.category, this.productKey});
  final String path;
  final String category;
  final String? productKey;
}

class FieldCaptureProduct {
  const FieldCaptureProduct({required this.key, required this.fields,
    required this.rating, required this.shortlisted, required this.bestSeller, required this.newProduct});
  final String key;
  final Map<String, String> fields;
  final int rating;
  final bool shortlisted;
  final bool bestSeller;
  final bool newProduct;
  String get name => fields['name'] ?? '';
  Map<String, Object?> get details => {
    for (final key in ['materials', 'dimensions', 'colours', 'packaging',
      'carton_dimensions', 'tooling_cost', 'customisation']) key: fields[key] ?? '',
    'best_seller': bestSeller, 'new_product': newProduct,
  };
}

class FieldCaptureResult {
  final List<FieldCaptureProduct> products;
  final List<FieldCapturePhoto> photos;
  final int tripId;
  final String name;
  final String booth;
  final String hall;
  final String category;
  final String country;
  final String notes;
  final int rating;
  final bool shortlisted;
  final String contactName;
  final String contactRole;
  final String phone;
  final String whatsapp;
  final String wechat;
  final String email;
  final String productName;
  final String model;
  final double? price;
  final double? moq;
  final String leadTime;
  final String paymentTerms;
  final String nextAction;
  final DateTime? followUpDate;
  final String meetingNotes;
  final Map<String, Object?> productDetails;
  final Map<String, Object?> meetingCommitments;
  final Map<String, Object?> fieldCapture;

  const FieldCaptureResult({
    this.products = const [],
    this.photos = const [],
    required this.tripId,
    required this.name,
    required this.booth,
    required this.hall,
    required this.category,
    required this.country,
    required this.notes,
    required this.rating,
    required this.shortlisted,
    required this.contactName,
    required this.contactRole,
    required this.phone,
    required this.whatsapp,
    required this.wechat,
    required this.email,
    required this.productName,
    required this.model,
    required this.price,
    required this.moq,
    required this.leadTime,
    required this.paymentTerms,
    required this.nextAction,
    required this.followUpDate,
    required this.meetingNotes,
    required this.productDetails,
    required this.meetingCommitments,
    required this.fieldCapture,
  });
}

class FieldCaptureChecklistDialog extends StatefulWidget {
  final String captureScope;
  final List<Trip> trips;
  final int selectedTripId;
  final String defaultCountry;
  final Map<String, String> prefill;

  const FieldCaptureChecklistDialog({
    super.key,
    required this.captureScope,
    required this.trips,
    required this.selectedTripId,
    required this.defaultCountry,
    required this.prefill,
  });

  @override
  State<FieldCaptureChecklistDialog> createState() =>
      _FieldCaptureChecklistDialogState();
}

class _FieldCaptureChecklistDialogState
    extends State<FieldCaptureChecklistDialog> {
  final _formKey = GlobalKey<FormState>();
  var _step = 0;
  late int _tripId;
  var _rating = 0;
  var _shortlisted = false;
  var _companyType = 'Not recorded';
  var _oemOdm = 'Not recorded';
  var _auditStatus = 'Not reviewed';
  var _nextAction = 'Follow up';
  DateTime? _followUpDate;
  final _checked = <String>{};
  final _photos = <FieldCapturePhoto>[];
  final _products = <FieldCaptureProduct>[];
  String _productKey = 'product_${DateTime.now().microsecondsSinceEpoch}';
  int _productRating = 0;
  bool _productShortlisted = false;
  final _scroll = ScrollController();
  bool _capturing = false;
  String? _error;
  static const _titles = ['Supplier & booth', 'Company profile', 'Contact person',
    'Product & pricing', 'Certifications', 'Conversation', 'Review & save'];
  static const _descriptions = [
    'Identify the supplier and remember where you met.',
    'Record capabilities relevant to your sourcing needs.',
    'Keep the right contact and their preferred communication details.',
    'Capture the product, specifications and indicative terms.',
    'Record what you saw. Verification can follow after the fair.',
    'Summarize the discussion and commitments on both sides.',
    'Check the essentials and choose the next action.',
  ];

  late final TextEditingController _name;
  late final TextEditingController _booth;
  late final TextEditingController _hall;
  late final TextEditingController _category;
  late final TextEditingController _country;
  final _notes = TextEditingController();
  final _factoryLocation = TextEditingController();
  final _exportMarkets = TextEditingController();
  final _capacity = TextEditingController();
  final _employeeCount = TextEditingController();
  final _factorySize = TextEditingController();
  final _certifications = TextEditingController();
  final _contactName = TextEditingController();
  final _contactRole = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _wechat = TextEditingController();
  final _email = TextEditingController();
  final _productName = TextEditingController();
  final _model = TextEditingController();
  final _price = TextEditingController();
  final _moq = TextEditingController();
  final _leadTime = TextEditingController();
  final _paymentTerms = TextEditingController();
  final _meetingNotes = TextEditingController();
  final _materials = TextEditingController();
  final _dimensions = TextEditingController();
  final _colours = TextEditingController();
  final _packaging = TextEditingController();
  final _cartonDimensions = TextEditingController();
  final _toolingCost = TextEditingController();
  final _customisation = TextEditingController();
  final _supplierCommitment = TextEditingController();
  final _ourCommitment = TextEditingController();
  var _bestSeller = false;
  var _newProduct = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.prefill;
    _contactName.text = seed['person'] ?? '';
    _contactRole.text = seed['role'] ?? '';
    _phone.text = seed['phone'] ?? '';
    _email.text = seed['email'] ?? '';
    _whatsapp.text = seed['whatsapp'] ?? '';
    _wechat.text = seed['wechat'] ?? '';
    _notes.text = seed['notes'] ?? '';
    _tripId = widget.selectedTripId;
    _name = TextEditingController(text: seed['name'] ?? '');
    _booth = TextEditingController(text: seed['booth'] ?? '');
    _hall = TextEditingController(text: seed['hall'] ?? '');
    _category = TextEditingController(text: seed['category'] ?? '');
    _country = TextEditingController(
        text: (seed['country']?.isNotEmpty ?? false)
            ? seed['country']
            : widget.defaultCountry);
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in [
      _name,
      _booth,
      _hall,
      _category,
      _country,
      _notes,
      _factoryLocation,
      _exportMarkets,
      _capacity,
      _employeeCount,
      _factorySize,
      _certifications,
      _contactName,
      _contactRole,
      _phone,
      _whatsapp,
      _wechat,
      _email,
      _productName,
      _model,
      _price,
      _moq,
      _leadTime,
      _paymentTerms,
      _meetingNotes,
      _materials,
      _dimensions,
      _colours,
      _packaging,
      _cartonDimensions,
      _toolingCost,
      _customisation,
      _supplierCommitment,
      _ourCommitment,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Choose due date';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _followUpDate = picked);
  }

  void _finish() {
    if (_name.text.trim().isEmpty) {
      setState(() => _step = 0);
      setState(() => _error = 'Enter a supplier name before saving.');
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    if (!_commitProduct()) {
      setState(() { _step = 3; _error = 'Enter a product name to link the product photos.'; });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final checklist = _checked.toList()..sort();
    Navigator.pop(
      context,
      FieldCaptureResult(
        products: List.unmodifiable(_products),
        photos: List.unmodifiable(_photos),
        tripId: _tripId,
        name: _name.text.trim(),
        booth: _booth.text.trim(),
        hall: _hall.text.trim(),
        category: _category.text.trim(),
        country: _country.text.trim(),
        notes: _notes.text.trim(),
        rating: _rating,
        shortlisted: _shortlisted,
        contactName: _contactName.text.trim(),
        contactRole: _contactRole.text.trim(),
        phone: _phone.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        wechat: _wechat.text.trim(),
        email: _email.text.trim(),
        productName: _productName.text.trim(),
        model: _model.text.trim(),
        price: double.tryParse(_price.text.trim()),
        moq: double.tryParse(_moq.text.trim()),
        leadTime: _leadTime.text.trim(),
        paymentTerms: _paymentTerms.text.trim(),
        nextAction: _nextAction,
        followUpDate: _followUpDate,
        meetingNotes: _meetingNotes.text.trim(),
        productDetails: {
          'materials': _materials.text.trim(),
          'dimensions': _dimensions.text.trim(),
          'colours': _colours.text.trim(),
          'packaging': _packaging.text.trim(),
          'carton_dimensions': _cartonDimensions.text.trim(),
          'tooling_cost': _toolingCost.text.trim(),
          'customisation': _customisation.text.trim(),
          'best_seller': _bestSeller,
          'new_product': _newProduct,
        },
        meetingCommitments: {
          'supplier': _supplierCommitment.text.trim(),
          'ours': _ourCommitment.text.trim(),
          'checklist': checklist,
        },
        fieldCapture: {
          'company_type': _companyType,
          'factory_location': _factoryLocation.text.trim(),
          'export_markets': _exportMarkets.text.trim(),
          'production_capacity': _capacity.text.trim(),
          'employee_count': _employeeCount.text.trim(),
          'factory_size': _factorySize.text.trim(),
          'oem_odm': _oemOdm,
          'audit_status': _auditStatus,
          'certifications_observed': _certifications.text.trim(),
          'checklist': checklist,
          'captured_at': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  Widget _stepHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: (_step + 1) / 7),
          const SizedBox(height: 10),
          Text('Step ${_step + 1} of 7',
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _basicStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Supplier and booth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (widget.trips.isEmpty)
            const Text('Create a trip first to save a supplier.')
          else
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _tripId,
              decoration: const InputDecoration(labelText: 'Trip'),
              items: widget.trips
                  .where((trip) => trip.id != null)
                  .map((trip) =>
                      DropdownMenuItem(value: trip.id, child: Text(trip.name)))
                  .toList(),
              onChanged: (value) => _tripId = value ?? _tripId,
            ),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Supplier name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Supplier name is required'
                : null,
          ),
          TextFormField(
              controller: _booth,
              decoration: const InputDecoration(labelText: 'Booth')),
          TextFormField(
              controller: _hall,
              decoration: const InputDecoration(labelText: 'Hall / zone')),
          TextFormField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category')),
          TextFormField(
              controller: _country,
              decoration: const InputDecoration(labelText: 'Country')),
          _photoSection('stand', 'Expo stand photos', 'Remember the booth, signage and display.'),
        ],
      );

  Widget _companyStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Company and capability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _companyType,
            decoration: const InputDecoration(labelText: 'Company type'),
            items: const ['Not recorded', 'Manufacturer', 'Trading company']
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) =>
                setState(() => _companyType = value ?? _companyType),
          ),
          TextFormField(
              controller: _factoryLocation,
              decoration: const InputDecoration(labelText: 'Factory location')),
          TextFormField(
              controller: _exportMarkets,
              decoration: const InputDecoration(labelText: 'Export markets')),
          TextFormField(
              controller: _capacity,
              decoration:
                  const InputDecoration(labelText: 'Production capacity')),
          TextFormField(
              controller: _employeeCount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Employee count')),
          TextFormField(
              controller: _factorySize,
              decoration: const InputDecoration(labelText: 'Factory size')),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _oemOdm,
            decoration: const InputDecoration(labelText: 'OEM / ODM'),
            items: const ['Not recorded', 'OEM', 'ODM', 'OEM + ODM', 'No']
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) => setState(() => _oemOdm = value ?? _oemOdm),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _auditStatus,
            decoration:
                const InputDecoration(labelText: 'Factory audit status'),
            items: const [
              'Not reviewed',
              'Requested',
              'Completed',
              'Passed',
              'Failed'
            ]
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) =>
                setState(() => _auditStatus = value ?? _auditStatus),
          ),
        ],
      );

  Widget _contactStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Person met',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextFormField(
              controller: _contactName,
              decoration: const InputDecoration(labelText: 'Person met')),
          TextFormField(
              controller: _contactRole,
              decoration:
                  const InputDecoration(labelText: 'Role / designation')),
          TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone')),
          TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp')),
          TextFormField(
              controller: _wechat,
              decoration: const InputDecoration(labelText: 'WeChat')),
          TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email')),
          _photoSection('person', 'Person you met', 'Ask permission before taking or saving their photo.'),
        ],
      );

  Widget _productStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Product and commercial terms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('${_products.length} products added', style: Theme.of(context).textTheme.titleSmall),
          for (final product in _products) Card(child: ListTile(
            title: Text(product.name),
            subtitle: Text('${product.fields['model'] ?? ''} | ${product.rating}/5${product.shortlisted ? " | Shortlisted" : ""}\n${_photos.where((photo) => photo.productKey == product.key).length} photos'),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Edit product', onPressed: () => _editProduct(product), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Remove product', onPressed: () => _removeProduct(product), icon: const Icon(Icons.delete_outline)),
            ]),
          )),
          const Divider(),
          Text(_products.any((product) => product.key == _productKey) ? 'Edit product' : 'Add a product',
            style: Theme.of(context).textTheme.titleMedium),
          TextFormField(
              controller: _productName,
              decoration: const InputDecoration(labelText: 'Product seen')),
          TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model / SKU')),
          _photoSection('product', 'Product photos', 'Add multiple views, packaging and product labels.'),
          TextFormField(
              controller: _materials,
              decoration: const InputDecoration(labelText: 'Materials')),
          TextFormField(
              controller: _dimensions,
              decoration: const InputDecoration(labelText: 'Dimensions')),
          TextFormField(
              controller: _colours,
              decoration:
                  const InputDecoration(labelText: 'Colours / finishes')),
          TextFormField(
              controller: _packaging,
              decoration: const InputDecoration(labelText: 'Packaging')),
          TextFormField(
              controller: _cartonDimensions,
              decoration:
                  const InputDecoration(labelText: 'Carton dimensions')),
          TextFormField(
              controller: _toolingCost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tooling cost')),
          TextFormField(
              controller: _customisation,
              decoration: const InputDecoration(
                  labelText: 'Customisation / logo options')),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _bestSeller,
            title: const Text('Best seller'),
            onChanged: (value) => setState(() => _bestSeller = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _newProduct,
            title: const Text('New product'),
            onChanged: (value) => setState(() => _newProduct = value),
          ),
          TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Indicative booth price (not an official quote)')),
          TextFormField(
              controller: _moq,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'MOQ')),
          TextFormField(
              controller: _leadTime,
              decoration: const InputDecoration(labelText: 'Lead time')),
          TextFormField(
              controller: _paymentTerms,
              decoration: const InputDecoration(labelText: 'Payment terms')),
          DropdownButtonFormField<int>(key: ValueKey('rating-$_productKey-$_productRating'),
            initialValue: _productRating, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product rating'),
            items: List.generate(6, (value) => DropdownMenuItem(value: value, child: Text('$value / 5'))),
            onChanged: (value) => setState(() => _productRating = value ?? 0)),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
            title: const Text('Shortlist this product'), value: _productShortlisted,
            onChanged: (value) => setState(() => _productShortlisted = value)),
          FilledButton.tonalIcon(onPressed: () {
            if (_productName.text.trim().isEmpty) {
              setState(() => _error = 'Enter a product name before adding it.');
              return;
            }
            if (_commitProduct()) setState(() => _error = null);
          }, icon: const Icon(Icons.add), label: const Text('Save product & add another')),
          const Text('Next also includes the product currently being edited. Each product has its own photos and shortlist decision.'),
        ],
      );

  Widget _certificateStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Certificates observed at the booth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
              'This is a quick observation. Add certificate numbers, expiry dates, proof, and verification in the supplier Certificate register after saving.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          TextFormField(
              controller: _certifications,
              decoration: const InputDecoration(
                  labelText: 'Certificate types seen (comma separated)')),
        ],
      );

  Widget _meetingStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Meeting outcome and commitments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Discussed at booth',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: const [
              'Price',
              'MOQ',
              'Payment',
              'Lead time',
              'Samples',
              'Certificates',
              'Factory audit'
            ]
                .map((label) => FilterChip(
                      label: Text(label),
                      selected: _checked.contains(label),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _checked.add(label);
                        } else {
                          _checked.remove(label);
                        }
                      }),
                    ))
                .toList(),
          ),
          TextFormField(
              controller: _supplierCommitment,
              decoration:
                  const InputDecoration(labelText: 'Supplier commitment')),
          TextFormField(
              controller: _ourCommitment,
              decoration: const InputDecoration(labelText: 'Our commitment')),
          TextFormField(
            controller: _meetingNotes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Meeting summary'),
          ),
        ],
      );

  Widget _decisionStep() => Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review and next action',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Container(width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Text(_name.text.trim().isEmpty ? 'Supplier name missing' : _name.text.trim(),
                style: Theme.of(context).textTheme.titleMedium),
              Text('Booth: ${_booth.text.trim().isEmpty ? "Not recorded" : _booth.text.trim()}'),
              if (_contactName.text.trim().isNotEmpty) Text('Contact: ${_contactName.text.trim()}'),
              Text('${_products.length} products'),
              for (final product in _products) Text('${product.name} | ${product.rating}/5${product.shortlisted ? " | Shortlisted" : ""}'),
              Text('${_photos.length} photos attached'),
            ])),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _rating,
            decoration: const InputDecoration(labelText: 'Initial rating'),
            items: List.generate(
                6,
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value / 5'))),
            onChanged: (value) => setState(() => _rating = value ?? _rating),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _shortlisted,
            title: const Text('Shortlist this supplier'),
            onChanged: (value) => setState(() => _shortlisted = value ?? false),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _nextAction,
            decoration: const InputDecoration(labelText: 'Next action'),
            items: const [
              'Follow up',
              'Request quote',
              'Request sample',
              'Request certificates',
              'Factory audit',
              'No action',
            ]
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) =>
                setState(() => _nextAction = value ?? _nextAction),
          ),
          if (_nextAction != 'No action')
            OutlinedButton.icon(
              onPressed: _pickDueDate,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(_dateLabel(_followUpDate)),
            ),
          TextFormField(controller: _notes, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Additional supplier notes')),
        ],
      );

  Future<void> _addPhoto(String category, ImageSource source) async {
    if (_capturing) return;
    setState(() { _capturing = true; _error = null; });
    try {
      Future<XFile?> pick() => ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2400);
      final image = source == ImageSource.camera ? await CameraCaptureService.capture(pick) : await pick();
      if (image == null || !mounted) return;
      final root = await getApplicationDocumentsDirectory();
      final folder = Directory('${root.path}/attachments/${widget.captureScope}/field_photos');
      await folder.create(recursive: true);
      final suffix = image.path.split('.').last.toLowerCase();
      final extension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(suffix) ? suffix : 'jpg';
      final saved = await File(image.path).copy('${folder.path}/${category}_${DateTime.now().microsecondsSinceEpoch}.$extension');
      if (mounted) {
        setState(() => _photos.add(FieldCapturePhoto(path: saved.path, category: category,
            productKey: category == 'product' ? _productKey : null)));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not add the photo. Existing entries are unchanged; please retry.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Widget _photoSection(String category, String title, String description) {
    final photos = _photos.where((photo) => photo.category == category &&
        (category != 'product' || photo.productKey == _productKey)).toList();
    return Container(width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _capturing ? null : () => _addPhoto(category, ImageSource.camera),
            icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Take photo')),
          TextButton.icon(onPressed: _capturing ? null : () => _addPhoto(category, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('From gallery')),
        ]),
        if (photos.isNotEmpty) Wrap(spacing: 12, runSpacing: 12, children: [
          for (final photo in photos) SizedBox(width: 112, child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(photo.path),
              width: 112, height: 88, fit: BoxFit.cover, cacheWidth: 336,
              errorBuilder: (_, error, stack) => const SizedBox(height: 88, child: Center(child: Text('Photo unavailable'))))),
            TextButton(onPressed: _capturing ? null : () => setState(() => _photos.remove(photo)),
              child: const Text('Remove')),
          ])),
        ]),
      ]));
  }

  void _move(int direction) {
    if (direction > 0 && !_formKey.currentState!.validate()) return;
    if (direction > 0 && _step == 3 && !_commitProduct()) return;
    FocusScope.of(context).unfocus();
    setState(() { _step += direction; _error = null; });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Map<String, TextEditingController> get _productControllers => {
    'name': _productName, 'model': _model, 'price': _price, 'moq': _moq,
    'lead_time': _leadTime, 'payment_terms': _paymentTerms, 'materials': _materials,
    'dimensions': _dimensions, 'colours': _colours, 'packaging': _packaging,
    'carton_dimensions': _cartonDimensions, 'tooling_cost': _toolingCost,
    'customisation': _customisation,
  };

  bool _commitProduct() {
    final fields = {for (final entry in _productControllers.entries) entry.key: entry.value.text.trim()};
    final hasPhoto = _photos.any((photo) => photo.productKey == _productKey);
    final hasInput = fields.values.any((value) => value.isNotEmpty) || hasPhoto ||
        _productRating != 0 || _productShortlisted || _bestSeller || _newProduct;
    if (!hasInput && !_products.any((product) => product.key == _productKey)) return true;
    if (fields['name']!.isEmpty) {
      setState(() => _error = 'Enter a name for this product, or clear its details and photos.');
      return false;
    }
    for (final key in ['price', 'moq']) {
      final value = fields[key]!;
      final number = double.tryParse(value);
      if (value.isNotEmpty && (number == null || !number.isFinite || number < 0)) {
        setState(() => _error = 'Enter a valid non-negative ${key == "price" ? "price" : "MOQ"}.');
        return false;
      }
    }
    final product = FieldCaptureProduct(key: _productKey, fields: Map.unmodifiable(fields),
        rating: _productRating, shortlisted: _productShortlisted, bestSeller: _bestSeller, newProduct: _newProduct);
    final index = _products.indexWhere((item) => item.key == _productKey);
    if (index < 0) { _products.add(product); } else { _products[index] = product; }
    _resetProduct();
    return true;
  }

  void _resetProduct() {
    for (final controller in _productControllers.values) { controller.clear(); }
    _productKey = 'product_${DateTime.now().microsecondsSinceEpoch}';
    _productRating = 0;
    _productShortlisted = false;
    _bestSeller = false;
    _newProduct = false;
  }

  void _editProduct(FieldCaptureProduct product) {
    if (_productKey != product.key && !_commitProduct()) return;
    setState(() {
      _productKey = product.key;
      for (final entry in _productControllers.entries) { entry.value.text = product.fields[entry.key] ?? ''; }
      _productRating = product.rating;
      _productShortlisted = product.shortlisted;
      _bestSeller = product.bestSeller;
      _newProduct = product.newProduct;
      _error = null;
    });
  }

  Future<void> _removeProduct(FieldCaptureProduct product) async {
    final remove = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Remove product?'), content: Text('Remove ${product.name} and its photos from this capture?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove'))],
    ));
    if (!mounted || remove != true) return;
    setState(() {
      _products.removeWhere((item) => item.key == product.key);
      _photos.removeWhere((photo) => photo.productKey == product.key);
      if (_productKey == product.key) _resetProduct();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [_basicStep, _companyStep, _contactStep, _productStep,
      _certificateStep, _meetingStep, _decisionStep];
    return PopScope(canPop: !_capturing, child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 720, height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 20, 16, 16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Supplier capture', style: theme.textTheme.titleLarge)),
                IconButton(tooltip: 'Cancel capture', onPressed: _capturing ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
              ]),
              _stepHeader(),
              const SizedBox(height: 12),
              Text(_titles[_step], style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_descriptions[_step], style: theme.textTheme.bodySmall),
            ])),
          const Divider(height: 1),
          if (_capturing) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12),
            child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))),
          Expanded(child: AbsorbPointer(absorbing: _capturing, child: Form(key: _formKey,
            child: SingleChildScrollView(controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]()),
            )))),
          const Divider(height: 1),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            TextButton(onPressed: _capturing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            const Spacer(),
            if (_step > 0) TextButton(onPressed: _capturing ? null : () => _move(-1), child: const Text('Back')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _capturing || widget.trips.isEmpty ? null : _step == 6 ? _finish : () => _move(1),
              child: Text(_step == 6 ? 'Save capture' : 'Next')),
          ]))),
        ])),
    ));
  }
}
