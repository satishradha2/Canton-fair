import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class FieldCaptureResult {
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
  final List<Trip> trips;
  final int selectedTripId;
  final String defaultCountry;
  final Map<String, String> prefill;

  const FieldCaptureChecklistDialog({
    super.key,
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
    if (!_formKey.currentState!.validate()) {
      setState(() => _step = 0);
      return;
    }
    final checklist = _checked.toList()..sort();
    Navigator.pop(
      context,
      FieldCaptureResult(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Supplier and booth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (widget.trips.isEmpty)
            const Text('Create a trip first to save a supplier.')
          else
            DropdownButtonFormField<int>(
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
        ],
      );

  Widget _companyStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Company and capability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          DropdownButtonFormField<String>(
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
            initialValue: _oemOdm,
            decoration: const InputDecoration(labelText: 'OEM / ODM'),
            items: const ['Not recorded', 'OEM', 'ODM', 'OEM + ODM', 'No']
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) => setState(() => _oemOdm = value ?? _oemOdm),
          ),
          DropdownButtonFormField<String>(
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
        ],
      );

  Widget _productStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Product and commercial terms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextFormField(
              controller: _productName,
              decoration: const InputDecoration(labelText: 'Product seen')),
          TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model / SKU')),
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
        ],
      );

  Widget _certificateStep() => Column(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review and next action',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          DropdownButtonFormField<int>(
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
        ],
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Canton Fair capture'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepHeader(),
                  const SizedBox(height: 18),
                  IndexedStack(
                    index: _step,
                    children: [
                      _basicStep(),
                      _companyStep(),
                      _contactStep(),
                      _productStep(),
                      _certificateStep(),
                      _meetingStep(),
                      _decisionStep(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          if (_step > 0)
            TextButton(
                onPressed: () => setState(() => _step--),
                child: const Text('Back')),
          FilledButton(
            onPressed: widget.trips.isEmpty
                ? null
                : _step == 6
                    ? _finish
                    : () => setState(() => _step++),
            child: Text(_step == 6 ? 'Save capture' : 'Next'),
          ),
        ],
      );
}
