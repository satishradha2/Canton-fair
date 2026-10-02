import 'dart:io';
import 'package:flutter/material.dart';

/// Decorative preview feedback only; border detection remains in the native scanner.
class AnimatedCardPreview extends StatefulWidget {
  const AnimatedCardPreview({super.key, this.path, required this.back, required this.processing});
  final String? path;
  final bool back, processing;
  @override
  State<AnimatedCardPreview> createState() => _AnimatedCardPreviewState();
}

class _AnimatedCardPreviewState extends State<AnimatedCardPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _reducedMotion = false;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reducedMotion = media.disableAnimations || media.accessibleNavigation;
    _configureMotion();
  }
  @override
  void didUpdateWidget(covariant AnimatedCardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureMotion();
  }
  void _configureMotion() {
    if (!_reducedMotion && (widget.processing || widget.path == null)) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }
  @override
  void dispose() { _motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = widget.path != null;
    return Semantics(label: widget.processing ? 'Reading ${widget.back ? 'back' : 'front'} card image' :
      hasImage ? 'Captured ${widget.back ? 'back' : 'front'} card preview' : 'Card alignment guide, not a live camera', child:
      RepaintBoundary(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: 1.7,
        child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [colors.primaryContainer.withAlpha(100), colors.surface, colors.secondaryContainer.withAlpha(70)])),
          child: Stack(fit: StackFit.expand, children: [
            AnimatedSwitcher(duration: Duration(milliseconds: _reducedMotion ? 0 : 320), child: hasImage ?
              TweenAnimationBuilder<double>(key: ValueKey(widget.path), tween: Tween(begin: .96, end: 1),
                duration: Duration(milliseconds: _reducedMotion ? 0 : 380), curve: Curves.easeOutCubic,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Padding(padding: const EdgeInsets.all(12), child: Image.file(File(widget.path!), fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) => const Center(child: Text('Image unavailable. Retake this side.'))))) :
              Padding(key: const ValueKey('guide'), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.contact_mail_outlined, size: 36, color: colors.primary),
                  const SizedBox(height: 10),
                  Flexible(child: Text(widget.back ? 'Back of card' : 'Front of card', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center)),
                  const SizedBox(height: 4),
                  const Flexible(child: Text('Keep all four edges visible', textAlign: TextAlign.center)),
                ]))),
            IgnorePointer(child: AnimatedBuilder(animation: _motion, builder: (context, _) => CustomPaint(
              painter: _CardFramePainter(color: colors.primary, phase: _motion.value,
                sweep: widget.processing && hasImage && !_reducedMotion, pulse: !hasImage && !_reducedMotion)))),
            Positioned(top: 10, left: 10, child: AnimatedSwitcher(duration: Duration(milliseconds: _reducedMotion ? 0 : 220),
              child: Container(key: ValueKey('${widget.processing}:$hasImage'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: colors.surface.withAlpha(240), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.primary.withAlpha(45))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.processing ? Icons.auto_awesome_outlined : hasImage ? Icons.check_circle_outline : Icons.crop_free,
                    color: colors.primary, size: 14), const SizedBox(width: 5),
                  Text(widget.processing ? 'Reading card' : hasImage ? 'Image captured' : 'Scan guide', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ])))),
          ]),
        ),
      ))));
  }
}

class _CardFramePainter extends CustomPainter {
  const _CardFramePainter({required this.color, required this.phase, required this.sweep, required this.pulse});
  final Color color;
  final double phase;
  final bool sweep, pulse;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final frame = rect.deflate(18);
    final paint = Paint()..color = color.withAlpha(pulse ? (130 + 85 * phase).round() : 200)
      ..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    const length = 20.0;
    final corners = Path()
      ..moveTo(frame.left, frame.top + length)..lineTo(frame.left, frame.top)..lineTo(frame.left + length, frame.top)
      ..moveTo(frame.right - length, frame.top)..lineTo(frame.right, frame.top)..lineTo(frame.right, frame.top + length)
      ..moveTo(frame.right, frame.bottom - length)..lineTo(frame.right, frame.bottom)..lineTo(frame.right - length, frame.bottom)
      ..moveTo(frame.left + length, frame.bottom)..lineTo(frame.left, frame.bottom)..lineTo(frame.left, frame.bottom - length);
    canvas.drawPath(corners, paint);
    if (sweep) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(frame, const Radius.circular(10)));
      final y = frame.top + frame.height * phase;
      final glow = Rect.fromLTRB(frame.left, y - 24, frame.right, y + 24);
      canvas.drawRect(glow, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withAlpha(0), color.withAlpha(55), color.withAlpha(0)]).createShader(glow));
      canvas.drawLine(Offset(frame.left + 4, y), Offset(frame.right - 4, y), Paint()..color = color.withAlpha(190)..strokeWidth = 1.5);
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant _CardFramePainter oldDelegate) => oldDelegate.color != color || oldDelegate.phase != phase || oldDelegate.sweep != sweep || oldDelegate.pulse != pulse;
}
