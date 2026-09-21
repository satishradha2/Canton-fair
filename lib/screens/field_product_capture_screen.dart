import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/camera_capture_service.dart';
import '../data/field_work_repository.dart';

class FieldProductCaptureScreen extends StatefulWidget {
  const FieldProductCaptureScreen({super.key, required this.scope,
    required this.supplierId, required this.supplierName});
  final String scope;
  final int supplierId;
  final String supplierName;
  @override
  State<FieldProductCaptureScreen> createState() => _FieldProductCaptureScreenState();
}

class _FieldProductCaptureScreenState extends State<FieldProductCaptureScreen> {
  final _repository = FieldWorkRepository();
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _photos = <String>[];
  late Future<List<Map<String, Object?>>> _categories;
  bool _busy = false;
  bool _shortlisted = false;
  bool _dirty = false;
  bool _allowExit = false;
  int _rating = 0;
  int _saved = 0;
  String? _error;

  TextEditingController _controller(String key) => _fields.putIfAbsent(key,
      () => TextEditingController(text: key == 'price_currency' ? 'USD' : ''));

  @override
  void initState() {
    super.initState();
    _categories = _repository.categories(widget.scope);
  }

  @override
  void dispose() {
    for (final controller in _fields.values) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Discard this unsaved product?'),
        content: const Text('Previously saved products are kept. This form and its selected photos have not been saved.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard'))]));
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _photo(ImageSource source) async {
    setState(() { _busy = true; _error = null; });
    try {
      Future<XFile?> pick() => ImagePicker().pickImage(
        source: source, imageQuality: 90, maxWidth: 2400);
      final photo = source == ImageSource.camera
          ? await CameraCaptureService.capture(pick) : await pick();
      if (photo != null && mounted) {
        setState(() {
          _photos.add(photo.path); _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not capture the photo. Your form is still here.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(bool another) async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      await _repository.captureProduct(scope: widget.scope,
        supplier: widget.supplierId,
        fields: {for (final entry in _fields.entries) entry.key: entry.value.text},
        rating: _rating, shortlisted: _shortlisted, photos: List.of(_photos));
      if (!mounted) return;
      if (another) {
        setState(() {
          for (final entry in _fields.entries) {
            if (entry.key != 'category' && entry.key != 'price_currency') entry.value.clear();
          }
          _photos.clear(); _rating = 0; _shortlisted = false;
          _dirty = false; _saved++;
        });
        _form.currentState!.reset();
      } else {
        setState(() { _dirty = false; _allowExit = true; });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {bool required = false,
      bool numeric = false, bool multiline = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(controller: _controller(key), enabled: !_busy,
      minLines: multiline ? 2 : 1, maxLines: multiline ? 4 : 1,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true)
          : multiline ? TextInputType.multiline : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _dirty = true,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return '$label is required';
        if (numeric && text.isNotEmpty) {
          final number = double.tryParse(text);
          if (number == null || !number.isFinite || number < 0) return 'Enter a non-negative number';
        }
        return null;
      },
    ));

  Future<void> _createCategory() async {
    final name = TextEditingController();
    final created = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Create product category'),
      content: TextField(controller: name, autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Category name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
    ));
    if (created != true || name.text.trim().isEmpty || !mounted) return;
    try {
      final category = await _repository.createCategory(widget.scope, name.text);
      if (!mounted) return;
      setState(() {
        _controller('category').text = category;
        _categories = _repository.categories(widget.scope);
        _dirty = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not create category: $error');
    }
  }

  Widget _categoryPicker() => FutureBuilder<List<Map<String, Object?>>(
    future: _categories,
    builder: (context, snapshot) {
      final names = (snapshot.data ?? const <Map<String, Object?>>[])
          .map((category) => category['name'] as String).toList();
      final selected = names.contains(_controller('category').text)
          ? _controller('category').text : null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          value: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Product category'),
          hint: const Text('Choose a category'),
          items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: _busy ? null : (value) => setState(() {
            _controller('category').text = value ?? '';
            _dirty = true;
          }),
          validator: (value) => value == null ? 'Product category is required' : null,
        ),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: _busy ? null : _createCategory,
          icon: const Icon(Icons.add), label: const Text('Create category'))),
      ]);
    },
  );

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 18), child: Padding(
      padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18), ...children,
        ])));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) _leave(); },
    child: Scaffold(
      appBar: AppBar(title: const Text('Capture product'),
        leading: IconButton(onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back))),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(16),
          child: Semantics(liveRegion: true, child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)))),
        Expanded(child: Form(key: _form, child: ListView(
          padding: const EdgeInsets.all(20), children: [
            Text(widget.supplierName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_saved > 0 ? '$_saved product(s) saved. Capture the next one.'
              : 'Keep the product, commercial details and evidence together.'),
            const SizedBox(height: 20),
            _section('Product identity', [
              _field('name', 'Product name', required: true),
              _categoryPicker(),
              const SizedBox(height: 16),
              _field('model_code', 'Model / SKU'),
              _field('specs', 'Description and specifications', multiline: true),
            ]),
            _section('Product photos', [
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton.icon(onPressed: _busy ? null : () => _photo(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo')),
                OutlinedButton.icon(onPressed: _busy ? null : () => _photo(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [for (var i = 0; i < _photos.length; i++)
                SizedBox(width: 112, child: Column(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(
                    File(_photos[i]), height: 100, width: 112, fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const SizedBox(height: 100,
                      child: Center(child: Text('Photo unavailable'))))),
                  TextButton(onPressed: _busy ? null : () => setState(() {
                    _photos.removeAt(i); _dirty = true;
                  }), child: const Text('Remove')),
                ]))]),
            ]),
            _section('Commercial details', [
              _field('quoted_price', 'Quoted unit price', numeric: true),
              _field('price_currency', 'Currency code', required: true),
              _field('price_basis', 'Price basis / Incoterm'),
              _field('moq', 'Minimum order quantity', numeric: true),
              _field('quantity_unit', 'Quantity unit'),
              _field('lead_time', 'Lead time, including unit'),
              _field('payment_terms', 'Payment terms'),
            ]),
            Card(margin: const EdgeInsets.only(bottom: 18), child: ExpansionTile(
              title: const Text('Specifications, packaging and samples'),
              childrenPadding: const EdgeInsets.all(18), children: [
                for (final entry in const {
                  'materials': 'Materials', 'dimensions': 'Dimensions',
                  'colours': 'Colours', 'variants': 'Variants',
                  'packaging': 'Packaging', 'carton_dimensions': 'Carton dimensions',
                  'carton_weight': 'Carton weight, including unit',
                  'units_per_carton': 'Units per carton', 'price_breaks': 'Quantity price breaks',
                  'customisation': 'Customization / OEM', 'tooling_cost': 'Tooling cost and currency',
                  'sample_requirements': 'Sample requirements', 'notes': 'Other notes',
                }.entries) _field(entry.key, entry.value),
              ])),
            _section('Your decision', [
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Shortlist this product'),
                value: _shortlisted, onChanged: _busy ? null : (value) => setState(() {
                  _shortlisted = value; _dirty = true;
                })),
              DropdownButtonFormField<int>(key: ValueKey('rating-$_rating-$_saved'),
                initialValue: _rating, decoration: const InputDecoration(labelText: 'Rating'),
                items: [for (var i = 0; i <= 5; i++) DropdownMenuItem(value: i,
                  child: Text(i == 0 ? 'Not rated' : '$i / 5'))],
                onChanged: _busy ? null : (value) => setState(() {
                  _rating = value ?? 0; _dirty = true;
                })),
              const SizedBox(height: 18), _field('shortlist_reason', 'Decision reason', multiline: true),
            ]),
          ]))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
            OutlinedButton(onPressed: _busy ? null : () => _save(true),
              child: const Text('Save & add another')),
            FilledButton(onPressed: _busy ? null : () => _save(false), child: const Text('Save product')),
          ]))),
      ]),
    ),
  );
}
