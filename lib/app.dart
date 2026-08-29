import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/captures_screen.dart';
import 'screens/shortlist_screen.dart';
import 'screens/followup_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/export_screen.dart';
import 'screens/settings_screen.dart';

class CantonFairApp extends StatefulWidget {
  const CantonFairApp({super.key});

  @override
  State<CantonFairApp> createState() => _CantonFairAppState();
}

class _CantonFairAppState extends State<CantonFairApp> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    CapturesScreen(),
    ShortlistScreen(),
    FollowUpScreen(),
    AnalyticsScreen(),
    ExportScreen(),
    SettingsScreen(),
  ];

  final _titles = const [
    'Dashboard',
    'Captures',
    'Shortlist',
    'Follow-Ups',
    'Analytics',
    'Export',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
      ),
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.record_voice_over), label: 'Capture'),
          NavigationDestination(icon: Icon(Icons.star), label: 'Shortlist'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Follow-ups'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.file_upload), label: 'Export'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
