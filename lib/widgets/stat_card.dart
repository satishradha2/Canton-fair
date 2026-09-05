import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 30, height: 30,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18)),
        const Spacer(),
        Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      ]),
      const Spacer(),
      Text('$value', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
    ]),
  );
}
