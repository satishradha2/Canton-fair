import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/record_search.dart';
import 'package:image_picker/image_picker.dart';
import '../data/fair_capture_service.dart';
import '../data/field_work_repository.dart';
import '../data/product_ai_service.dart';
import '../data/product_capture_service.dart';
import '../data/supplier_categories_service.dart';
import '../models/models.dart';
import 'supplier_voice_note_screen.dart';
import '../widgets/product_audio_notes.dart';
import '../widgets/focused_workspace.dart';

class ProductCaptureWorkspaceScreen extends StatefulWidget {
  const ProductCaptureWorkspaceScreen({super.key, required this.scope, required this.company,
    this.productId, this.fairId, this.readOnly = false, this.visitKey});
  final String scope;
  final Exhibitor company;
  final int? productId;
  final int? fairId;
  final bool readOnly;
  final String? visitKey;
  @override
  State<ProductCaptureWorkspaceScreen> createState() => _ProductCaptureWorkspaceScreenState();
}

class _ProductCaptureWorkspaceScreenState extends State<ProductCaptureWorkspaceScreen> with WidgetsBindingObserver {
  String _additionalCategoryQuery = '';
  int _panel = 0;
  static const labels = {
    'name': 'Product name', 'model_code': 'Model / SKU', 'specs': 'Description',
    'moq': 'Minimum order quantity', 'quoted_price': 'Quoted unit price', 'price_currency': 'Currency code',
    'quantity_unit': 'Quantity unit', 'lead_time': 'Lead time (include unit)', 'payment_terms': 'Payment terms',
    'price_basis': 'Price basis / Incoterm', 'price_breaks': 'Quantity price breaks',
    'packaging': 'Packaging', 'carton_dimensions': 'Carton dimensions', 'carton_weight': 'Carton weight (include unit)',
    'units_per_carton': 'Units per carton', 'production_capacity': 'Production capacity',
    'customisation': 'Branding / customisation', 'tooling_cost': 'Tooling cost and currency',
    'sample_requirements': 'Sample availability / requirements', 'sample_cost': 'Sample cost and currency',
    'sample_lead_time': 'Sample delivery time', 'certifications': 'Supplier-stated certifications',
    'warranty': 'Warranty', 'notes': 'Product notes',
  };
  static const photoRoles = ['Product view', 'Packaging', 'Specification sheet', 'Price label', 'Brochure'];
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _photos = <Map<String, dynamic>>[];
  final _specs = <Map<String, dynamic>>[];
  final _additionalCategories = <String>{};
  List<dynamic> _quoteHistory = [];
  List<String> _categories = [];
  List<Trip> _fairs = [];
  int? _fairId;
  int? _productId;
  bool _shortlisted = false;
  bool _alsoShortlistSupplier = false;
  final _shortlistReason = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _aiPending = false;
  bool _allowExit = false;
  String? _error;
  String _draftStatus = 'Draft saves automatically on this phone';
  Map<String, dynamic>? _aiCache;
  Timer? _timer;
  Future<void> _draftWrites = Future.value();

  TextEditingController _controller(String key) => _fields.putIfAbsent(key,
      () => TextEditingController(text: key == 'price_currency' ? 'USD' : ''));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _productId = widget.productId;
    _fairId = widget.fairId;
    _load();
  }

  Future<void> _load() async {
    try {
      await ProductCaptureService.checkScope(widget.scope);
      _categories = (await FieldWorkRepository().categories(widget.scope)).map((row) => row['name'] as String).toList();
      final preferred = SupplierCategoriesService.selected(widget.company);
      _categories.sort((a,b) {
        final priority = (preferred.contains(a) ? 0 : 1).compareTo(preferred.contains(b) ? 0 : 1);
        return priority == 0 ? a.compareTo(b) : priority;
      });
      _fairs = await FairCaptureService.fairs();
      final stored = !widget.readOnly ? await ProductCaptureService.loadDraft(widget.scope, widget.company.id!, _productId) : null;
      final data = stored ?? (_productId == null ? null : await ProductCaptureService.loadProduct(_productId!));
      if (data != null) {
        final fields = Map<String, dynamic>.from(data['fields'] as Map);
        for (final entry in fields.entries) { _controller(entry.key).text = entry.value?.toString() ?? ''; }
        _photos.addAll((data['photos'] as List).map((row) => Map<String, dynamic>.from(row as Map)));
        _specs.addAll((data['specifications'] as List).map((row) => Map<String, dynamic>.from(row as Map)));
        _additionalCategories.addAll(List<String>.from(data['additional_categories'] as List? ?? []));
        _quoteHistory = List<dynamic>.from(data['quote_history'] as List? ?? []);
        _fairId = data['fair_id'] as int? ?? _fairId;
        _shortlisted = data['shortlisted'] == true;
        _shortlistReason.text = data['shortlist_reason']?.toString() ?? '';
        _alsoShortlistSupplier = data['also_shortlist_supplier'] == true;
        _aiPending = data['ai_pending'] == true;
        _aiCache = data['ai_cache'] is Map ? Map<String, dynamic>.from(data['ai_cache'] as Map) : null;
        if (stored != null) _draftStatus = 'Your saved draft has been restored';
      }
      if (_fairs.length == 1 && _fairId == null) _fairId = _fairs.first.id;
      if (!_fairs.any((fair) => fair.id == _fairId)) _fairId = null;
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) setState(() { _error = 'Could not open product: $error'; _loading = false; });
    }
  }

  Map<String, dynamic> _snapshot() => {
    'fields': {for (final entry in _fields.entries) entry.key: entry.value.text},
    'photos': _photos.map((row) => Map<String, dynamic>.from(row)).toList(),
    'specifications': _specs.map((row) => Map<String, dynamic>.from(row)).toList(),
    'fair_id': _fairId, 'shortlisted': _shortlisted, 'ai_pending': _aiPending, 'ai_cache': _aiCache,
    'shortlist_reason': _shortlistReason.text, 'also_shortlist_supplier': _alsoShortlistSupplier,
    'visit_key': widget.visitKey,
    'quote_history': _quoteHistory, 'additional_categories': _additionalCategories.toList(),
  };

  void _changed() {
    if (widget.readOnly) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 650), _queueDraft);
  }

  void _queueDraft() {
    final data = _snapshot();
    final id = _productId;
    _draftWrites = _draftWrites.then((_) async {
      try {
        await ProductCaptureService.writeDraft(widget.scope, widget.company.id!, id, data);
        if (mounted) setState(() => _draftStatus = 'Draft saved on this phone');
      } catch (error) {
        if (mounted) setState(() => _draftStatus = 'Draft could not save: $error');
      }
    });
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!widget.readOnly) {
      _timer?.cancel(); _queueDraft(); await _draftWrites;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
  }

  @override
  void dispose() {
    _shortlistReason.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final field in _fields.values) { field.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_loading && !_busy && !widget.readOnly && !_allowExit && state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _queueDraft();
    }
  }

  Future<void> _addPhotos(ImageSource source, {String role = 'Product view'}) async {
    setState(() { _busy = true; _error = null; });
    try {
      final picker = ImagePicker();
      final List<XFile> images;
      if (source == ImageSource.gallery) {
        images = await picker.pickMultiImage(imageQuality: 90, maxWidth: 2400);
      } else {
        final image = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 2400);
        images = image == null ? [] : [image];
      }
      for (final image in images) {
        final path = await ProductCaptureService.keepPhoto(widget.scope, widget.company.id!, image.path);
        if (_photos.any((photo) => photo['path'] == path)) continue;
        _photos.add({'path': path, 'role': role, 'cover': _photos.isEmpty && role == 'Product view'});
      }
      _changed();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not add photos: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _showImage(String path) async {
    await showDialog<void>(context: context, builder: (context) => Dialog(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: InteractiveViewer(child: Image.file(File(path), errorBuilder: (_,error,stack) => const Padding(padding: EdgeInsets.all(24), child: Text('Image is unavailable on this phone. Sync to download it.'))))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ]),
    ));
  }

  void _removePhoto(int index) {
    final path = _photos[index]['path'];
    if (_specs.any((row) => _sourcePath(row) == path)) {
      setState(() => _error = 'This image is a source for specification rows. Remove those rows first to remove the image.');
      return;
    }
    setState(() => _photos.removeAt(index));
    _changed();
  }

  String? _sourcePath(Map<String, dynamic> row) {
    if (row['source_key'] != null) {
      for (final photo in _photos) { if (photo['source_key'] == row['source_key']) return photo['path'] as String; }
    }
    return row['source'] as String?;
  }

  Future<void> _editSpecification([int? index]) async {
    final old = index == null ? <String, dynamic>{} : _specs[index];
    final label = TextEditingController(text: old['label'] as String? ?? '');
    final value = TextEditingController(text: old['value'] as String? ?? '');
    final unit = TextEditingController(text: old['unit'] as String? ?? '');
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
      title: Text(index == null ? 'Add specification' : 'Edit specification'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: label, decoration: const InputDecoration(labelText: 'Specification'), validator: (text) => text == null || text.trim().isEmpty ? 'Enter a label' : null),
        TextFormField(controller: value, decoration: const InputDecoration(labelText: 'Value'), minLines: 1, maxLines: 3),
        TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Unit (optional)')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, {...old, 'label': label.text.trim(), 'value': value.text.trim(), 'unit': unit.text.trim()}); }, child: const Text('Use row'))],
    ));
    Future<void>.delayed(const Duration(milliseconds: 400), () { label.dispose(); value.dispose(); unit.dispose(); });
    if (result != null && mounted) {
      setState(() { if (index == null) { _specs.add(result); } else { _specs[index] = result; } });
      _changed();
    }
  }

  Future<void> _extract() async {
    if (_photos.isEmpty) { setState(() => _error = 'Add specification or brochure images first.'); return; }
    final selected = <int>{for (var i=0; i<_photos.length; i++) if (_photos[i]['role'] != 'Product view' && _photos[i]['role'] != 'Packaging') i};
    if (selected.isEmpty) selected.add(0);
    final sources = await showModalBottomSheet<List<String>>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .65, child: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Choose up to six images for AI extraction. Selected images will be sent to OpenAI.')),
        Expanded(child: ListView(children: [for (var i=0; i<_photos.length; i++) CheckboxListTile(
          title: Text('Image ${i+1}: ${_photos[i]['role']}'), value: selected.contains(i),
          secondary: Image.file(File(_photos[i]['path'] as String), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_,error,stack) => const Icon(Icons.broken_image)),
          onChanged: (checked) => setSheet(() { if (checked == true) { selected.add(i); } else { selected.remove(i); } }),
        )])),
        Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: selected.isEmpty || selected.length > 6 ? null : () => Navigator.pop(context, (selected.toList()..sort()).map((index) => _photos[index]['path'] as String).toList()), child: Text('Extract from ${selected.length} images'))),
      ])))));
    if (sources == null || !mounted) return;
    setState(() { _busy = true; _aiPending = true; _error = null; });
    _timer?.cancel(); _queueDraft(); await _draftWrites;
    try {
      final cache = await ProductAiService.extract(widget.scope, sources, _categories, _aiCache);
      if (!mounted) return;
      _aiCache = cache;
      final result = Map<String, dynamic>.from(cache['result'] as Map);
      _aiPending = false;
      await _reviewAi(result, sources);
    } catch (error) {
      if (mounted) setState(() => _error = 'AI extraction is pending: $error. Continue manually or retry when connected.');
    } finally {
      if (mounted) { setState(() => _busy = false); _changed(); }
    }
  }

  Future<void> _reviewAi(Map<String, dynamic> result, List<String> sources) async {
    final suggestions = Map<String, dynamic>.from(result['fields'] as Map);
    final rows = (result['specifications'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    final useFields = <String>{for (final key in suggestions.keys) if (suggestions[key].toString().isNotEmpty && _controller(key).text.trim().isEmpty) key};
    final useRows = <int>{for (var i=0; i<rows.length; i++) i};
    bool useCategory = _controller('category').text.isEmpty && _categories.contains(result['category']);
    final accepted = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .85, child: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Review AI suggestions. Select a field explicitly to replace an existing value.')),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final warning in result['warnings'] as List) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(warning.toString()))),
          if (_categories.contains(result['category'])) CheckboxListTile(title: Text('Category: ${result['category']}'), value: useCategory, onChanged: (checked) => setSheet(() => useCategory = checked == true)),
          for (final entry in suggestions.entries.where((entry) => entry.value.toString().isNotEmpty)) CheckboxListTile(
            title: Text(labels[entry.key] ?? entry.key), subtitle: Text('${entry.value}${_controller(entry.key).text.isEmpty ? '' : '\nCurrent: ${_controller(entry.key).text}'}'),
            value: useFields.contains(entry.key), onChanged: (checked) => setSheet(() { if (checked == true) { useFields.add(entry.key); } else { useFields.remove(entry.key); } }),
          ),
          const Divider(), const Text('Specification table rows'),
          for (var i=0; i<rows.length; i++) CheckboxListTile(
            title: Text('${rows[i]['label']}: ${rows[i]['value']} ${rows[i]['unit']}'),
            subtitle: Text(rows[i]['review_note']?.toString() ?? ''), value: useRows.contains(i),
            onChanged: (checked) => setSheet(() { if (checked == true) { useRows.add(i); } else { useRows.remove(i); } }),
          ),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep draft unchanged')), const Spacer(), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply selected'))])),
      ])))));
    if (accepted != true || !mounted) return;
    setState(() {
      final reviewed = ProductAiService.applyReviewed(
        {for (final entry in _fields.entries) entry.key: entry.value.text}, suggestions, useFields);
      for (final entry in reviewed.entries) { _controller(entry.key).text = entry.value; }
      if (useCategory) _controller('category').text = result['category'] as String;
      for (final i in useRows) {
        final row = rows[i];
        final sourceIndex = row['source_index'] as int;
        final next = {...row, 'source': sources[sourceIndex]};
        if (!_specs.any((item) => item['label'] == next['label'] && item['value'] == next['value'] && item['unit'] == next['unit'])) _specs.add(next);
      }
    });
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Create category'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Category name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create'))],
    ));
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final category = await FieldWorkRepository().createCategory(widget.scope, name);
      if (!mounted) return;
      setState(() { if (!_categories.contains(category)) _categories.add(category); _controller('category').text = category; });
      _changed();
    } catch (error) { if (mounted) setState(() => _error = 'Could not create category: $error'); }
  }

  Future<void> _save(bool another, {bool voice = false}) async {
    if (_busy) return;
    if (!_form.currentState!.validate()) {
      setState(() { _panel = _controller('name').text.trim().isEmpty ||
        !_categories.contains(_controller('category').text) || _fairId == null ? 0 : 3;
        _error = 'Check the highlighted required fields in Basics and Pricing.'; });
      return;
    }
    setState(() { _busy = true; _error = null; });
    final draftId = _productId;
    try {
      _timer?.cancel(); _queueDraft(); await _draftWrites;
      final id = await ProductCaptureService.save(scope: widget.scope, supplier: widget.company.id!, product: _productId, draft: _snapshot());
      _productId = id;
      await ProductCaptureService.clearDraft(widget.scope, widget.company.id!, draftId);
      if (!mounted) return;
      if (voice) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierVoiceNoteScreen(productId: id, productName: _controller('name').text, contextLabel: 'Product: ${_controller('name').text}')));
        if (!mounted) return;
      }
      if (another) {
        setState(() {
          for (final entry in _fields.entries) { if (!['category','price_currency'].contains(entry.key)) entry.value.clear(); }
          _photos.clear(); _specs.clear(); _aiCache = null; _aiPending = false; _productId = null;
          _additionalCategories.clear(); _quoteHistory = [];
          _shortlisted = false; _alsoShortlistSupplier = false; _shortlistReason.clear();
          _draftStatus = 'Product saved. Ready for the next product.'; _panel = 0;
        });
      } else {
        setState(() => _allowExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
      }
    } catch (error) { if (mounted) setState(() => _error = 'Could not save product: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _field(String key, {bool required = false}) => Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(
    key: ValueKey('product-field-$key'),
    controller: _controller(key), enabled: !_busy && !widget.readOnly,
    minLines: 1, maxLines: ['specs','notes','price_breaks'].contains(key) ? 4 : 1,
    keyboardType: ['moq','quoted_price'].contains(key) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: labels[key] ?? key, border: const OutlineInputBorder()),
    onChanged: (_) => _changed(), validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) return 'This field is required.';
      if (['moq','quoted_price'].contains(key) && value != null && value.trim().isNotEmpty) {
        final number = double.tryParse(value); if (number == null || !number.isFinite || number < 0) return 'Enter a non-negative number.';
      }
      return null;
    },
  ));

  Widget _section(String title, List<Widget> children) => Card(margin: const EdgeInsets.only(bottom: 18), child: Padding(
    padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 16), ...children,
    ]),
  ));

  Future<void> _photoOptions(int index) async {
    final photo = _photos[index];
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: () => _showImage(photo['path'] as String), child: ClipRRect(
              borderRadius: BorderRadius.circular(16), child: Image.file(File(photo['path'] as String),
                height: 190, fit: BoxFit.contain, errorBuilder: (_, error, stack) => const Text('Photo unavailable. Sync to download.')))),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(initialValue: photoRoles.contains(photo['role']) ? photo['role'] as String : 'Product view',
              decoration: const InputDecoration(labelText: 'Image role'),
              items: photoRoles.map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
              onChanged: widget.readOnly || _busy ? null : (role) {
                setState(() => photo['role'] = role); update(() {}); _changed(); }),
            SwitchListTile(title: const Text('Cover image'), value: photo['cover'] == true,
              onChanged: widget.readOnly || _busy ? null : (value) {
                setState(() { if (value) { for (final item in _photos) { item['cover'] = false; } } photo['cover'] = value; });
                update(() {}); _changed(); }),
            if (!widget.readOnly) TextButton.icon(icon: const Icon(Icons.delete_outline),
              label: const Text('Remove image'), onPressed: _busy ? null : () {
                Navigator.pop(sheetContext); _removePhoto(index); }),
            TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Done')),
          ])))));
  }

  Widget _photoPanel() => _section('Photos and source documents', [
    if (!widget.readOnly) Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: _busy ? null : () => _addPhotos(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
      OutlinedButton.icon(onPressed: _busy ? null : () => _addPhotos(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Add photos')),
      OutlinedButton.icon(onPressed: _busy ? null : () => _addPhotos(ImageSource.camera, role: 'Specification sheet'), icon: const Icon(Icons.document_scanner_outlined), label: const Text('Spec sheet')),
    ]),
    const SizedBox(height: 12),
    Text('${_photos.length} images. Tap a thumbnail to view its role, cover status or remove it.'),
    const SizedBox(height: 12),
    if (_photos.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Icon(Icons.add_photo_alternate_outlined, size: 44)),
    LayoutBuilder(builder: (context, constraints) => GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _photos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: constraints.maxWidth > 600 ? 4 : 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .95),
      itemBuilder: (context, index) => Material(color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: () => _photoOptions(index), child: Column(children: [
          Expanded(child: SizedBox(width: double.infinity, child: Image.file(File(_photos[index]['path'] as String),
            fit: BoxFit.cover, errorBuilder: (_, error, stack) => const Icon(Icons.broken_image_outlined)))),
          Padding(padding: const EdgeInsets.all(8), child: Row(children: [
            if (_photos[index]['cover'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 16)),
            Expanded(child: Text(_photos[index]['role']?.toString() ?? 'Product view', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall)),
          ])),
        ]))))),
  ]);

  Widget _specActions(int index) => Wrap(spacing: 2, children: [
    if (_sourcePath(_specs[index]) != null) IconButton(tooltip: 'Source image', onPressed: () => _showImage(_sourcePath(_specs[index])!), icon: const Icon(Icons.image_outlined)),
    if (!widget.readOnly) IconButton(tooltip: 'Edit specification', onPressed: _busy ? null : () => _editSpecification(index), icon: const Icon(Icons.edit_outlined)),
    if (!widget.readOnly) IconButton(tooltip: 'Remove specification', onPressed: _busy ? null : () { setState(() => _specs.removeAt(index)); _changed(); }, icon: const Icon(Icons.delete_outline)),
  ]);

  Widget _specPanel() => _section('Specifications', [
    if (_aiPending) const Text('AI extraction pending. Sources and draft are saved on this phone.'),
    if (!widget.readOnly) Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(onPressed: _busy ? null : _extract, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Extract with AI')),
      TextButton.icon(onPressed: _busy ? null : () => _editSpecification(), icon: const Icon(Icons.add), label: const Text('Add specification')),
    ]),
    const SizedBox(height: 12),
    if (_specs.isEmpty) const Text('Add a specification sheet in Photos, or enter specifications manually.'),
    LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 700) {
        return Column(children: [for (var i=0; i<_specs.length; i++)
        Card(color: Theme.of(context).colorScheme.surfaceContainerLow, child: Padding(padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_specs[i]['label']?.toString() ?? '', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text([_specs[i]['value'], _specs[i]['unit']].where((value) => value != null && value.toString().isNotEmpty).join(' ')),
            Align(alignment: Alignment.centerRight, child: _specActions(i)),
          ])))]);
      }
      return SizedBox(width: double.infinity, child: DataTable(columnSpacing: 12,
        columns: const [DataColumn(label: Text('Specification')), DataColumn(label: Text('Value')), DataColumn(label: Text('Unit')), DataColumn(label: Text('Actions'))],
        rows: [for (var i=0; i<_specs.length; i++) DataRow(cells: [
          DataCell(SizedBox(width: constraints.maxWidth * .18, child: Text(_specs[i]['label']?.toString() ?? ''))),
          DataCell(SizedBox(width: constraints.maxWidth * .22, child: Text(_specs[i]['value']?.toString() ?? ''))),
          DataCell(SizedBox(width: 60, child: Text(_specs[i]['unit']?.toString() ?? ''))), DataCell(_specActions(i)),
        ])]));
    }),
    for (final row in _specs.where((row) => (row['review_note'] as String? ?? '').isNotEmpty))
      Padding(padding: const EdgeInsets.only(top: 8), child: Text('${row['label']}: ${row['review_note']}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
  ]);

  @override
  Widget build(BuildContext context) => PopScope(canPop: _allowExit,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) _leave(); },
    child: Scaffold(appBar: AppBar(title: Text(widget.readOnly ? 'Product details' : _productId == null ? 'Add product' : 'Update product'),
      leading: IconButton(onPressed: _busy ? null : _leave, icon: const Icon(Icons.arrow_back))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Form(key: _form,
        child: FocusedWorkspace(title: widget.company.name,
          subtitle: widget.readOnly ? 'Saved product / read-only' : _draftStatus, busy: _busy,
          index: _panel, onChanged: (index) => setState(() => _panel = index),
          labels: const ['Basics', 'Photos', 'Specifications', 'Pricing', 'Voice notes'],
          icons: const [Icons.inventory_2_outlined, Icons.photo_library_outlined, Icons.list_alt, Icons.payments_outlined, Icons.mic_none],
          notice: _error == null ? null : Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          sections: [
            ListView(key: const PageStorageKey('product-basics'), padding: const EdgeInsets.all(16), children: [_section('Product identity', [
            _field('name', required: true),
            SearchableSelectionField<String>(key: ValueKey(_controller('category').text), value: _categories.contains(_controller('category').text) ? _controller('category').text : null,
              decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
              options: _categories, labelFor: (name) => name,
              onChanged: _busy || widget.readOnly ? null : (name) { setState(() => _controller('category').text = name ?? ''); _changed(); },
              validator: (value) => value == null ? 'Select a category from Masters.' : null),
            if (!widget.readOnly) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy ? null : _createCategory, icon: const Icon(Icons.add), label: const Text('Create category'))),
            ExpansionTile(title: const Text('Additional categories (optional)'), children: [
              RecordSearchField(hint: 'Find an additional category',
                onChanged: (value) => setState(() => _additionalCategoryQuery = value)),
              const SizedBox(height: 10),
              if (!_categories.any((name) => name != _controller('category').text &&
                  recordMatches(_additionalCategoryQuery, [name])))
                const Text('No matching additional categories.'),
              Wrap(spacing: 6, runSpacing: 6, children: _categories.where((name) =>
                name != _controller('category').text && recordMatches(_additionalCategoryQuery, [name])).map((name) => FilterChip(
                label: Text(name), selected: _additionalCategories.contains(name),
                onSelected: _busy || widget.readOnly ? null : (selected) {
                  setState(() { if (selected) { _additionalCategories.add(name); } else { _additionalCategories.remove(name); } }); _changed();
                },
              )).toList()),
            ]),
            const SizedBox(height: 14),
            SearchableSelectionField<int>(key: ValueKey('fair-$_fairId'), value: _fairId,
              decoration: const InputDecoration(labelText: 'Captured at fair *', border: OutlineInputBorder()),
              options: _fairs.map((fair) => fair.id!).toList(),
              labelFor: (id) => _fairs.firstWhere((fair) => fair.id == id).name,
              onChanged: _busy || widget.readOnly ? null : (id) { setState(() => _fairId = id); _changed(); }, validator: (value) => value == null ? 'Select a fair.' : null),
            const SizedBox(height: 14), _field('model_code'), _field('specs'), _field('moq'),
          ])]),
            ListView(key: const PageStorageKey('product-photos'), padding: const EdgeInsets.all(16), children: [_photoPanel()]),
            ListView(key: const PageStorageKey('product-specs'), padding: const EdgeInsets.all(16), children: [_specPanel()]),
            ListView(key: const PageStorageKey('product-pricing'), padding: const EdgeInsets.all(16), children: [
          _section('Price and ordering', [
            for (final key in ['quoted_price', 'price_currency', 'quantity_unit', 'price_basis', 'price_breaks'])
              _field(key, required: key == 'price_currency'),
          ]),
          _section('Delivery and supply', [
            for (final key in ['lead_time', 'payment_terms', 'packaging', 'carton_dimensions',
              'carton_weight', 'units_per_carton', 'production_capacity', 'customisation', 'tooling_cost'])
              _field(key),
          ]),
          _section('Samples and assurance', [
            for (final key in ['sample_requirements', 'sample_cost', 'sample_lead_time',
              'certifications', 'warranty']) _field(key),
          ]),
          _section('Product notes', [_field('notes')]),
          if (_quoteHistory.isNotEmpty) Card(child: ExpansionTile(title: const Text('Quotation history'), children: [
            for (final quote in _quoteHistory.reversed) ListTile(
              title: Text('${quote['currency']} ${quote['price']} / ${quote['quantity_unit'] ?? 'unit'}'),
              subtitle: Text('MOQ ${quote['moq'] ?? '-'} · ${quote['fair_name'] ?? ''}\n${quote['recorded_at']}\n${quote['recorded_by']}'),
            ),
          ])),
          SwitchListTile(title: const Text('Product of interest / shortlisted'), value: _shortlisted,
            onChanged: _busy || widget.readOnly ? null : (value) { setState(() => _shortlisted = value); _changed(); }),
          if (_shortlisted) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
            controller: _shortlistReason, enabled: !_busy && !widget.readOnly, onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Product shortlist reason (optional)', border: OutlineInputBorder()))),
          if (_shortlisted && !widget.readOnly) CheckboxListTile(title: const Text('Also shortlist this supplier'),
            subtitle: const Text('Optional. Removing this product later will not remove the supplier shortlist.'),
            value: _alsoShortlistSupplier, onChanged: _busy ? null : (value) { setState(() => _alsoShortlistSupplier = value == true); _changed(); }),]),
            ListView(key: const PageStorageKey('product-audio'), padding: const EdgeInsets.all(16), children: [
              if (_productId != null) ProductAudioNotes(scope: widget.scope, productId: _productId!, productName: _controller('name').text, canEdit: !widget.readOnly && !_busy)
              else _section('Product voice notes', [const Text('Save this product first so every recording stays linked to this product and supplier.'),
                const SizedBox(height: 16), if (!widget.readOnly) FilledButton.icon(onPressed: _busy ? null : () => _save(false, voice: true), icon: const Icon(Icons.mic_none), label: const Text('Save and record voice note'))]),
            ]),
          ],
          footer: widget.readOnly ? null : Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : () => _save(false), icon: const Icon(Icons.check), label: const Text('Save product'))),
            Row(children: [Expanded(child: TextButton(onPressed: _busy ? null : () => _save(true), child: const Text('Save & add another'))),
              Expanded(child: TextButton.icon(onPressed: _busy ? null : () => _save(false, voice: true), icon: const Icon(Icons.mic_none), label: const Text('Save + voice note')))]),
          ]),
        ))));
}
