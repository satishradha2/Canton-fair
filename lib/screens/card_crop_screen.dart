import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CardCropScreen extends StatefulWidget {
  const CardCropScreen({super.key, required this.path});
  final String path;
  @override
  State<CardCropScreen> createState() => _CardCropScreenState();
}

class _CardCropScreenState extends State<CardCropScreen> {
  static const _channel = MethodChannel('canton_fair_crm/card_image');
  String? _preview;
  String? _error;
  double _ratio = 1.6;
  bool _busy = true;
  bool _detected = false;
  int? _drag;
  List<Offset> _corners = [Offset.zero, const Offset(1, 0), const Offset(1, 1), const Offset(0, 1)];

  @override
  void initState() { super.initState(); _prepare(); }

  Future<void> _prepare() async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('prepare', {'path': widget.path});
      if (!mounted || data == null) return;
      setState(() {
        _preview = data['path'] as String;
        _ratio = (data['width'] as num) / (data['height'] as num);
        _detected = data['detected'] == true;
        _corners = (data['corners'] as List).map((point) =>
            Offset((point[0] as num).toDouble(), (point[1] as num).toDouble())).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Automatic edge detection is unavailable. Keep the original and continue OCR.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() { _busy = true; _error = null; });
    try {
      final path = await _channel.invokeMethod<String>('crop', {
        'path': _preview, 'corners': _corners.map((p) => [p.dx, p.dy]).toList(),
      });
      if (mounted) Navigator.pop(context, path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Corners must form a non-crossing card outline. Adjust them or keep the original.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Crop and straighten')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(_detected
            ? 'Edges detected. Drag the four handles to include the entire card.'
            : 'Drag the four handles around the card. The original will be preserved.')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(child: LayoutBuilder(builder: (context, bounds) {
          if (_preview == null) return const SizedBox.shrink();
          final width = math.min(bounds.maxWidth, bounds.maxHeight * _ratio);
          final height = width / _ratio;
          return Center(child: SizedBox(width: width, height: height, child: GestureDetector(
            onPanStart: _busy ? null : (event) {
              var nearest = 65.0;
              _drag = null;
              for (var i = 0; i < _corners.length; i++) {
                final distance = (Offset(_corners[i].dx * width, _corners[i].dy * height) - event.localPosition).distance;
                if (distance < nearest) { nearest = distance; _drag = i; }
              }
            },
            onPanUpdate: _busy ? null : (event) {
              if (_drag == null) return;
              setState(() => _corners[_drag!] = Offset(
                (event.localPosition.dx / width).clamp(0.0, 1.0),
                (event.localPosition.dy / height).clamp(0.0, 1.0),
              ));
            },
            onPanEnd: (_) => _drag = null,
            child: Stack(fit: StackFit.expand, children: [
              Image.file(File(_preview!), fit: BoxFit.fill),
              CustomPaint(painter: _Outline(List<Offset>.from(_corners))),
            ]),
          )));
        })),
        Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 8, runSpacing: 8, children: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Keep original')),
          TextButton(onPressed: _busy ? null : () => setState(() => _corners = [Offset.zero, const Offset(1, 0), const Offset(1, 1), const Offset(0, 1)]), child: const Text('Full image')),
          FilledButton(onPressed: _busy || _preview == null ? null : _apply, child: const Text('Apply crop')),
        ])),
      ])),
    ),
  );
}

class _Outline extends CustomPainter {
  const _Outline(this.corners);
  final List<Offset> corners;
  @override
  void paint(Canvas canvas, Size size) {
    final points = corners.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = Colors.tealAccent..style = PaintingStyle.stroke..strokeWidth = 3);
    for (final point in points) {
      canvas.drawCircle(point, 11, Paint()..color = Colors.white);
      canvas.drawCircle(point, 7, Paint()..color = Colors.teal);
    }
  }
  @override
  bool shouldRepaint(covariant _Outline oldDelegate) => true;
}
