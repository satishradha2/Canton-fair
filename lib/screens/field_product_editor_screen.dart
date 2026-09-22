import 'package:flutter/material.dart';

import '../data/field_work_repository.dart';

class FieldProductEditorScreen extends StatefulWidget {
  const FieldProductEditorScreen({
    super.key,
    required this.scope,
    required this.supplierId,
    required this.supplierName,
    required this.product,
  });

  final String scope;
  final int supplierId;
  final String supplierName;
  final Map<String, Object?> product;

  @override
  State<FieldProductEditorScreen> createState() =>
      _FieldProductEditorScreenState();
}

class _FieldProductEditorScreenState extends State<FieldProductEditorScreen> {
  static const _createCategoryOption = '__create_new_product_category__';
  final _repository = FieldWorkRepository();
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late Future<List<Map<String, Object?>>> _categories;
  bool _shortlisted = false;
  bool _busy = false;
  String? _error;

  TextEditingController _controller(String key, [String value = '']) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: value));

  @override
  void initState() {
    super.initState();
    _categories = _repository.categories(widget.scope);
    _shortlisted = widget.product['shortlisted'] == 1;
    _controller('name', widget.product['name'] as String? ?? '');
    _controller('category', widget.product['category'] as String? ?? '');
    _controller('model_code', widget.product['model_code'] as String? ?? '');
    _controller('quoted_price', widget.product['quoted_price']?.toString() ?? '');
    _controller('price_currency', widget.product['price_currency'] as String? ?? 'USD');
    _controller('moq', widget.product['moq']?.toString() ?? '');
    _controller('lead_time', widget.product['lead_time'] as String? ?? '');
    _controller('specs', widget.product['specs'] as String? ?? '');
    _controller(
      'payment_terms',
      widget.product['payment_terms'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.updateProduct(
        scope: widget.scope,
        supplier: widget.supplierId,
        product: widget.product['id'] as int,
        fields: {for (final entry in _fields.entries) entry.key: entry.value.text},
        shortlisted: _shortlisted,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label,
      {bool required = false, bool numeric = false, bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controller(key),
        enabled: !_busy,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 4 : 1,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : multiline
                ? TextInputType.multiline
                : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) return '$label is required';
          if (numeric && text.isNotEmpty) {
            final parsed = double.tryParse(text);
            if (parsed == null || !parsed.isFinite || parsed < 0) {
              return 'Enter a non-negative number';
            }
          }
          return null;
        },
      ),
    );
  }

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
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not create category: $error');
    }
  }

  Future<void> _selectCategory(String? value) async {
    if (value == _createCategoryOption) {
      await _createCategory();
      return;
    }
    if (value == null) return;
    setState(() => _controller('category').text = value);
  }

  Widget _categoryPicker() => FutureBuilder<List<Map<String, Object?>>>(
    future: _categories,
    builder: (context, snapshot) {
      final names = (snapshot.data ?? const <Map<String, Object?>>[])
          .map((category) => category['name'] as String).toList();
      final selected = names.contains(_controller('category').text)
          ? _controller('category').text : null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Product category'),
          hint: const Text('Choose a category'),
          items: [
            ...names.map(
                (name) => DropdownMenuItem(value: name, child: Text(name))),
            const DropdownMenuItem(
                value: _createCategoryOption,
                child: Text('+ Create new category')),
          ],
          onChanged: _busy ? null : _selectCategory,
          validator: (value) => value == null ? 'Product category is required' : null,
        ),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: _busy ? null : _createCategory,
          icon: const Icon(Icons.add), label: const Text('Create category'))),
      ]);
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit product')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.supplierName,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Update the field record. Existing photos remain attached.'),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              const SizedBox(height: 20),
              _field('name', 'Product name', required: true),
              _categoryPicker(),
              const SizedBox(height: 20),
              _field('model_code', 'Model / SKU'),
              _field('specs', 'Description and specifications', multiline: true),
              const Divider(height: 36),
              _field('quoted_price', 'Quoted unit price', numeric: true),
              _field('price_currency', 'Currency code'),
              _field('moq', 'Minimum order quantity', numeric: true),
              _field('lead_time', 'Lead time, including unit'),
              _field('payment_terms', 'Payment terms'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shortlist this product'),
                subtitle: const Text('Keep this product visible for sourcing follow-up.'),
                value: _shortlisted,
                onChanged: _busy ? null : (value) => setState(() => _shortlisted = value),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_busy ? 'Saving...' : 'Save product changes'),
              ),
            ],
          ),
        ),
      );
}
