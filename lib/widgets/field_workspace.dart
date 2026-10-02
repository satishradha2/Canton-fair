import 'package:flutter/material.dart';

/// Shared visual hierarchy for focused field workflows.
class FieldWorkspaceHeader extends StatelessWidget {
  const FieldWorkspaceHeader({super.key, required this.eyebrow,
    required this.title, required this.subtitle, this.icon = Icons.business_outlined});
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [colors.primary, colors.secondary],
          begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: colors.onPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: colors.onPrimary, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(eyebrow.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onPrimary, letterSpacing: 1.3)),
          const SizedBox(height: 6),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(
            color: colors.onPrimary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onPrimary, height: 1.5)),
        ])),
      ]),
    );
  }
}

class FieldWorkspaceSection extends StatelessWidget {
  const FieldWorkspaceSection({super.key, required this.title,
    required this.icon, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(icon, color: theme.colorScheme.secondary, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700)))]),
        if (subtitle != null) ...[const SizedBox(height: 6),
          Text(subtitle!, style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant))],
        const SizedBox(height: 18),
        child,
      ])));
  }
}
