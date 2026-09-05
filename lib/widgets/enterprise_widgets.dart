import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EnterprisePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final EdgeInsets padding;
  const EnterprisePage({super.key, required this.title, required this.subtitle,
    this.actions = const [], required this.children, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final gutter = constraints.maxWidth > 1240 ? (constraints.maxWidth - 1200) / 2 : padding.left;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, padding.top, gutter, padding.bottom + 24),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240),
          builder: (context, value, child) => Opacity(
            opacity: value, child: Transform.translate(offset: Offset(0, 6 * (1 - value)), child: child)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CANTON FAIR / SOURCING WORKSPACE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: AppColors.teal)),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
              child: Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted))),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  });
}

class SectionPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const SectionPanel({super.key, required this.title, this.subtitle, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ])),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 16),
      child,
    ]),
  ));
}

class MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const MetricPill({super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line)),
    child: Row(children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 21)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ])),
    ]),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFF4F8F7), Color(0xFFF8F9FA)]),
      borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
    child: Column(children: [
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: AppColors.teal, size: 28)),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted))),
    ]),
  );
}

class InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const InfoChip({super.key, required this.label, this.icon, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.12))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
      Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12, height: 1.3))),
    ]),
  );
}
