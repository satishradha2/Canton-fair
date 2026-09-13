import 'package:canton_fair_crm/data/language_service.dart';
import 'package:canton_fair_crm/screens/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['en', 'zh', 'hi']) {
    testWidgets('Google sign-in is offered in both auth modes: $language',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AppLanguage(code: language, child: const SignInScreen()),
      ));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SignInScreen));
      final google = find.widgetWithText(
          OutlinedButton, tr(context, 'googleOptional'));
      expect(google, findsOneWidget);
      expect(tester.widget<OutlinedButton>(google).onPressed, isNotNull);
      final create = find.text(tr(context, 'newAccount'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text(tr(context, 'createYourAccount')), findsOneWidget);
      expect(google, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
