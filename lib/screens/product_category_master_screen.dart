import 'package:flutter/material.dart';

import '../data/approval_policy.dart';
import '../data/field_work_repository.dart';
import '../data/team_workspace_service.dart';
import '../widgets/database_paged_list.dart';
import '../data/record_page_service.dart';

class ProductCategoryMasterScreen extends StatefulWidget {
  const ProductCategoryMasterScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ProductCategoryMasterScreen> createState() =>
      ProductCategoryMasterScreenState();
}

class ProductCategoryMasterScreenState extends State<ProductCategoryMasterScreen> {
  final _repository = FieldWorkRepository();
  final _workspace = TeamWorkspaceService();
  late Future<_CategoryData> _categories;
  bool _busy = false;
  String? _error;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _categories = _load();
  }

  Future<_CategoryData> _load() async {
    final scope = await _workspace.scopeKey();
    return _CategoryData(scope, const []);
  }

  Future<void> createCategory() => _createCategory();
  Future<void> _createCategory() async {
    try {
      await ApprovalPolicy.requireWriter();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create product category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'Example: Home decor',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _categories;
      await _repository.createCategory(data.scope, name);
      if (mounted) setState(() { _categories = _load(); _revision++; });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not create category: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.embedded ? null : AppBar(
          title: const Text('Product categories'),
          actions: [
            TextButton.icon(
              onPressed: _busy ? null : _createCategory,
              icon: const Icon(Icons.add),
              label: const Text('Create category'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: FutureBuilder<_CategoryData>(
          future: _categories,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load categories: ${snapshot.error}'),
              ));
            }
            return Padding(padding: const EdgeInsets.all(20), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Shared product master', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('Create categories here; find and select them during product capture.'),
              if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
              const SizedBox(height: 16),
              Expanded(child: DatabasePagedList(refreshToken: _revision,
                loader: RecordPageService.categories, searchHint: 'Search categories',
                emptyMessage: 'No product categories yet. Use Create category above.',
                itemBuilder: (_, item) => Card(child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: const Text('Available for product capture'))))),
            ]));          },
        ),
      );
}

class _CategoryData {
  const _CategoryData(this.scope, this.items);

  final String scope;
  final List<Map<String, Object?>> items;
}
