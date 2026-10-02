import 'package:flutter/material.dart';

/// Keeps every section mounted, preserving form fields, recordings and scroll.
class FocusedWorkspace extends StatelessWidget {
  const FocusedWorkspace({super.key, required this.title, required this.subtitle,
    required this.labels, required this.icons, required this.sections,
    required this.index, required this.onChanged, this.footer, this.notice,
    this.busy = false});
  final String title, subtitle;
  final List<String> labels;
  final List<IconData> icons;
  final List<Widget> sections;
  final int index;
  final ValueChanged<int> onChanged;
  final Widget? footer, notice;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [
          colors.secondaryContainer.withValues(alpha: .65),
          theme.scaffoldBackgroundColor])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          AnimatedSwitcher(duration: const Duration(milliseconds: 180),
            child: Text(subtitle, key: ValueKey(subtitle), maxLines: 2,
              overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
        ])),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(children: List.generate(labels.length, (i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(selected: index == i, button: true,
            child: InkWell(borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(i),
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                  color: index == i ? colors.primary : colors.surfaceContainerLow,
                  border: Border.all(color: index == i ? colors.primary : colors.outlineVariant)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icons[i], size: 18, color: index == i ? colors.onPrimary : colors.onSurfaceVariant),
                  const SizedBox(width: 7),
                  Text(labels[i], style: theme.textTheme.labelLarge?.copyWith(
                    color: index == i ? colors.onPrimary : colors.onSurface)),
                ])))))))),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      if (notice != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: notice!),
      Expanded(child: IndexedStack(index: index, children: List.generate(sections.length,
        (i) => TickerMode(enabled: index == i, child: sections[i])))),
      if (footer != null) Container(
        decoration: BoxDecoration(color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant))),
        child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: footer!))),
    ]);
  }
}
