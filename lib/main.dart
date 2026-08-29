import 'package:flutter/material.dart';
import 'app.dart';
import 'data/reminder_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService.initialize();
  runApp(
    MaterialApp(
      title: 'Canton Fair CRM',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const CantonFairApp(),
    ),
  );
}
