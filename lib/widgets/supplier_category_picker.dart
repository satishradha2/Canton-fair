import 'package:flutter/material.dart';

import '../data/field_work_repository.dart';

/// A shared, master-data-backed multi-category selector for supplier capture.
class SupplierCategoryPicker extends StatefulWidget {
  const SupplierCategoryPicker({
    super.key,
    required this.scope,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Product categories *',
  });

  final String scope;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final String label;

  @override
  State<SupplierCategoryPicker> createState() => _SupplierCategoryPickerState();
}

class _SupplierCategoryPickerState extends State<SupplierCategoryPicker> {
  final _repository = FieldWorkRepository();
  late Future<List<Map<String, Object?>>> _categories;

  @override
  void initState() {
    super.initState();
    _categories = _repository.categories(widget.scope);
  }

  Future<void> _chooseCategories() async {
    final categories = await _categories;
    if (!mounted) return;
    final selected = Set<String>.from(widget.selected);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select product categories',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Choose every category that applies to this supplier.'),
                const SizedBox(height: 12),
                Flexible(
                  child: categories.isEmpty
                      ? const Center(
                          child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'No active categories yet. Create one in Product categories first.'),
                        ))
                      : ListView(
                          shrinkWrap: true,
                          children: categories.map((row) {
                            final name = row['name'] as String;
                            return CheckboxListTile(
                              value: selected.contains(name),
                              title: Text(name),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) => setSheetState(() {
                                if (checked == true) {
                                  selected.add(name);
                                } else {
                                  selected.remove(name);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: Text(selected.isEmpty
                        ? 'Select at least one category'
                        : 'Use ${selected.length} categor${selected.length == 1 ? 'y' : 'ies'}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
        future: _categories,
        builder: (context, snapshot) {
          final errorText = widget.selected.isEmpty
              ? 'Select at least one category before saving.'
              : null;
          return InkWell(
            onTap: widget.enabled && snapshot.hasData ? _chooseCategories : null,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: errorText,
                suffixIcon: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.expand_more),
              ),
              child: snapshot.hasError
                  ? const Text('Categories could not be loaded. Try again later.')
                  : widget.selected.isEmpty
                      ? const Text('Select one or more categories')
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: (widget.selected.toList()..sort())
                              .map((name) => Chip(
                                    label: Text(name),
                                    onDeleted: widget.enabled
                                        ? () {
                                            final next =
                                                Set<String>.from(widget.selected)
                                                  ..remove(name);
                                            widget.onChanged(next);
                                          }
                                        : null,
                                  ))
                              .toList(),
                        ),
            ),
          );
        },
      );
}
