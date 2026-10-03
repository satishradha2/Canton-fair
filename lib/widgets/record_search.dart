import 'package:flutter/material.dart';

/// Each word can match a different part of the record, regardless of case.
bool recordMatches(String query, Iterable<Object?> values) {
  final text = values.where((value) => value != null).join(' ').toLowerCase();
  return query.toLowerCase().trim().split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty).every(text.contains);
}

class RecordSearchField extends StatefulWidget {
  const RecordSearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  State<RecordSearchField> createState() => _RecordSearchFieldState();
}

class _RecordSearchFieldState extends State<RecordSearchField> {
  final _controller = TextEditingController();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textInputAction: TextInputAction.search,
    onChanged: (value) { setState(() {}); widget.onChanged(value); },
    decoration: InputDecoration(hintText: widget.hint,
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: _controller.text.isEmpty ? null : IconButton(
        tooltip: 'Clear search', icon: const Icon(Icons.close_rounded),
        onPressed: () {
          _controller.clear(); setState(() {}); widget.onChanged('');
        })),
  );
}

/// Searchable master selection that retains standard Form validation.
class SearchableSelectionField<T> extends StatelessWidget {
  const SearchableSelectionField({super.key, required this.options,
    required this.labelFor, required this.decoration, required this.onChanged,
    this.value, this.validator});
  final List<T> options;
  final String Function(T) labelFor;
  final InputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) => FormField<T>(
    initialValue: value, validator: validator, enabled: onChanged != null,
    builder: (field) => InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onChanged == null ? null : () async {
        var query = '';
        final selected = await showModalBottomSheet<T>(
          context: context, isScrollControlled: true, showDragHandle: true,
          builder: (context) => StatefulBuilder(builder: (context, update) {
            final matches = options.where((option) =>
              recordMatches(query, [labelFor(option)])).toList();
            final media = MediaQuery.of(context);
            return Padding(padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SafeArea(top: false, child: SizedBox(
                height: (media.size.height - media.viewInsets.bottom) * 0.72,
                child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(decoration.labelText ?? 'Select an option',
                      style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    RecordSearchField(hint: 'Type to find...',
                      onChanged: (value) => update(() => query = value)),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('${matches.length} of ${options.length} options')),
                    Expanded(child: matches.isEmpty
                      ? Center(child: Text(options.isEmpty ? 'No options created yet.'
                        : 'No matches. Clear or change your search.'))
                      : ListView.builder(itemCount: matches.length,
                        itemBuilder: (_, index) => ListTile(
                          title: Text(labelFor(matches[index])),
                          trailing: matches[index] == field.value
                            ? const Icon(Icons.check_rounded) : null,
                          onTap: () => Navigator.pop(context, matches[index])))),
                    TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  ])),
              )));
          }),
        );
        if (!field.mounted || selected == null) return;
        field.didChange(selected);
        onChanged?.call(selected);
      },
      child: InputDecorator(
        isEmpty: field.value == null,
        decoration: decoration.copyWith(enabled: onChanged != null,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintText: '',
          errorText: field.errorText, suffixIcon: const Icon(Icons.expand_more)),
        child: Text(
          field.value == null
            ? decoration.hintText ?? 'Choose an option'
            : labelFor(field.value as T),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: field.value == null
            ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)
            : Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ),
  );
}
