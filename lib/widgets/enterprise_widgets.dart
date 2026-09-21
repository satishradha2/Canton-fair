import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EnterprisePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final EdgeInsets padding;
  const EnterprisePage(
      {super.key,
      required this.title,
      required this.subtitle,
      this.actions = const [],
      required this.children,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final gutter = constraints.maxWidth > 1240
            ? (constraints.maxWidth - 1200) / 2
            : padding.left;
        final topPadding = constraints.maxWidth < 480 ? 16.0 : padding.top;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FBF9), AppColors.surface],
              stops: [0, 0.38],
            ),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                gutter, topPadding, gutter, padding.bottom + 28),
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                        offset: Offset(0, 8 * (1 - value)), child: child)),
                child: Container(
                  padding: EdgeInsets.all(constraints.maxWidth < 480 ? 18 : 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12102C37),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.controlSelected,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('CANTON FAIR / SOURCING WORKSPACE',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.teal)),
                        ),
                        const SizedBox(height: 16),
                        Text(title,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Text(subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ))),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Wrap(spacing: 10, runSpacing: 10, children: actions),
                        ],
                      ]),
                ),
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        );
      });
}

class SectionPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const SectionPanel(
      {super.key,
      required this.title,
      this.subtitle,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final inset = compact ? 16.0 : 20.0;
          return Card(
              child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.teal, width: 4)),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
            padding: EdgeInsets.all(inset),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ])),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ]),
              SizedBox(height: compact ? 12 : 16),
              const Divider(),
              SizedBox(height: compact ? 12 : 16),
              child,
            ]),
          )));
        },
      );
}

class MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const MetricPill(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = adaptiveAppColor(context, color);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant)),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: accent, size: 21)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant)),
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: colors.surface, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.teal, size: 28)),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant))),
      ]),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const InfoChip(
      {super.key,
      required this.label,
      this.icon,
      this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAppColor(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.24))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6)
        ],
        Flexible(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.3))),
      ]),
    );
  }
}
