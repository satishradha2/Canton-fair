import 'package:canton_fair_crm/screens/settings_screen.dart';
import 'package:canton_fair_crm/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Settings screen shows app update entry point', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        // This widget test does not initialize authentication or use a network.
        home: SettingsScreen(workspaceLoader: () async => null),
      ),
    );

    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('App updates'), findsOneWidget);
  });
}
