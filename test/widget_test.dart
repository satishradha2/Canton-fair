import 'package:canton_fair_crm/app.dart';
import 'package:canton_fair_crm/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Canton Fair app opens on dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const CantonFairApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
