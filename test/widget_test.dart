import 'package:canton_fair_crm/screens/settings_screen.dart';
import 'package:canton_fair_crm/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Settings screen shows app update entry point', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const SettingsScreen(),
      ),
    );

    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('App updates'), findsOneWidget);
  });
}
