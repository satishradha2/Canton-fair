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
              _field('category', 'Category', required: true),
              FutureBuilder<List<Map<String, Object?>>>(
                future: _categories,
                builder: (context, snapshot) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in snapshot.data ?? const [])
                      ActionChip(
                        label: Text(category['name'] as String),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _controller('category').text =
                                category['name'] as String),
                      ),
                  ],
                ),
              ),
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
