import 'dart:ui';
import 'package:flutter/material.dart';

class EnterpriseGlassPanel extends StatelessWidget {
  const EnterpriseGlassPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

class EnterpriseActionTile extends StatefulWidget {
  const EnterpriseActionTile({super.key, required this.icon,
    required this.title, required this.subtitle, required this.onTap,
    this.highlight = false, this.busy = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool highlight;
  final bool busy;

  @override
  State<EnterpriseActionTile> createState() => _EnterpriseActionTileState();
}

class _EnterpriseActionTileState extends State<EnterpriseActionTile> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final disabled = widget.onTap == null || widget.busy;
    final foreground = widget.highlight ? colors.onPrimary : colors.onSurface;
    final reduced = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    return AnimatedScale(
      scale: _active && !disabled ? 0.98 : 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: widget.highlight ? colors.primary : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: widget.highlight
              ? colors.primary : colors.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : widget.onTap,
          onHighlightChanged: (value) => setState(() => _active = value),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.highlight
                        ? colors.onPrimary.withValues(alpha: 0.12)
                        : colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                  child: widget.busy
                      ? SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2,
                            color: foreground))
                      : Icon(widget.icon, size: 22, color: widget.highlight
                          ? foreground : colors.secondary),
                ),
                const Spacer(),
                Icon(disabled ? Icons.lock_outline : Icons.arrow_outward_rounded,
                    size: 16, color: foreground.withValues(alpha: 0.55)),
              ]),
              const SizedBox(height: 12),
              Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(widget.subtitle, style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground.withValues(alpha: 0.75))),
            ]),
          ),
        ),
      ),
    );
  }
}
