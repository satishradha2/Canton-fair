import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        elevation: 3,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            child: Icon(icon, color: color),
          ),
          title: Text(
            value.toString(),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(label),
        ),
      );
}

