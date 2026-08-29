import 'package:flutter/material.dart';
import 'app.dart';
import 'data/reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService.initialize();
  runApp(
    MaterialApp(
      title: 'Canton Fair CRM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const CantonFairApp(),
    ),
  );
}
