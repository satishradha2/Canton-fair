import 'package:flutter/material.dart';

import '../data/approval_policy.dart';
import '../data/field_work_repository.dart';
import '../data/team_workspace_service.dart';

class ProductCategoryMasterScreen extends StatefulWidget {
  const ProductCategoryMasterScreen({super.key});

  @override
  State<ProductCategoryMasterScreen> createState() =>
      _ProductCategoryMasterScreenState();
}

class _ProductCategoryMasterScreenState extends State<ProductCategoryMasterScreen> {
  final _repository = FieldWorkRepository();
  final _workspace = TeamWorkspaceService();
  late Future<_CategoryData> _categories;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categories = _load();
  }

  Future<_CategoryData> _load() async {
    final scope = await _workspace.scopeKey();
    return _CategoryData(scope, await _repository.categories(scope));
  }

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
      if (mounted) setState(() => _categories = _load());
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not create category: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
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
            final categories = snapshot.data!.items;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Shared product master',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text(
                  'Categories created here are available in the product-category dropdown on mobile and web.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _error = null),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                if (categories.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Icon(Icons.category_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text('No product categories yet',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('Create the first category before capturing products.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _createCategory,
                          icon: const Icon(Icons.add),
                          label: const Text('Create category'),
                        ),
                      ]),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: categories
                          .map((item) => ListTile(
                                leading: const Icon(Icons.category_outlined),
                                title: Text(item['name']?.toString() ?? ''),
                                subtitle: const Text('Available for product capture'),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _CategoryData {
  const _CategoryData(this.scope, this.items);

  final String scope;
  final List<Map<String, Object?>> items;
}
