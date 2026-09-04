import 'dart:io';

import 'package:flutter/material.dart';

class PhotoAnnotationScreen extends StatefulWidget {
  final String imagePath;
  final List<Map<String, dynamic>> initialAnnotations;

  const PhotoAnnotationScreen({
    super.key,
    required this.imagePath,
    required this.initialAnnotations,
  });

  @override
  State<PhotoAnnotationScreen> createState() => _PhotoAnnotationScreenState();
}

class _PhotoAnnotationScreenState extends State<PhotoAnnotationScreen> {
  late List<Map<String, dynamic>> _annotations;

  @override
  void initState() {
    super.initState();
    _annotations = widget.initialAnnotations
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _addAnnotation(Offset localPosition, Size size) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add photo note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'What should the team notice?',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add note')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _annotations.add({
        'x': (localPosition.dx / size.width).clamp(0.0, 1.0),
        'y': (localPosition.dy / size.height).clamp(0.0, 1.0),
        'text': text,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.imagePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo notes'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _annotations),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Tap the photo to mark a product detail, defect, or question for your team.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: file.existsSync()
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        onTapDown: (details) =>
                            _addAnnotation(details.localPosition, size),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Image.file(file, fit: BoxFit.contain),
                            ),
                            ..._annotations.asMap().entries.map((entry) {
                              final item = entry.value;
                              final x = (item['x'] as num? ?? 0.5).toDouble();
                              final y = (item['y'] as num? ?? 0.5).toDouble();
                              return Positioned(
                                left: (x * size.width - 16).clamp(0, size.width - 32),
                                top: (y * size.height - 16).clamp(0, size.height - 32),
                                child: Tooltip(
                                  message: item['text'] as String? ?? 'Photo note',
                                  child: Badge(
                                    label: Text('${entry.key + 1}'),
                                    child: const Icon(Icons.location_on,
                                        color: Colors.red, size: 32),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  )
                : const Center(child: Text('This photo is no longer available locally.')),
          ),
          if (_annotations.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _annotations.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(_annotations[index]['text'] as String? ?? ''),
                    trailing: IconButton(
                      tooltip: 'Remove photo note',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _annotations.removeAt(index)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
