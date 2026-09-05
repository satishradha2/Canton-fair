import 'dart:io';
import 'dart:ui' as ui;

import 'package:canton_fair_crm/screens/auth_gate.dart';
import 'package:canton_fair_crm/screens/settings_screen.dart';
import 'package:canton_fair_crm/theme/app_theme.dart';
import 'package:canton_fair_crm/widgets/enterprise_widgets.dart';
import 'package:canton_fair_crm/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('PublicSans');
    loader.addFont(rootBundle.load('assets/fonts/PublicSans.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> render(
    WidgetTester tester,
    Widget screen,
    String name,
    Size size, {
    double textScale = 1,
    double keyboardHeight = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          disableAnimations: true,
        ),
        child: RepaintBoundary(key: boundaryKey, child: child!),
      ),
      home: Scaffold(body: screen),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '$name must render without layout or framework exceptions');
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/visual-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final viewport in <String, Size>{
    'small-phone': const Size(360, 800),
    'phone': const Size(412, 915),
    'tablet': const Size(1280, 800),
  }.entries) {
    testWidgets('sign-in layout ${viewport.key}', (tester) async {
      await render(tester, const SignInScreen(), 'signin-${viewport.key}', viewport.value);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('settings layout ${viewport.key}', (tester) async {
      await render(tester, SettingsScreen(workspaceLoader: () async => null),
          'settings-${viewport.key}', viewport.value);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shared components ${viewport.key}', (tester) async {
      await render(tester, const _ComponentPreview(),
          'components-${viewport.key}', viewport.value);
    });
  }

  testWidgets('sign-in remains usable with keyboard and large text', (tester) async {
    await render(tester, const SignInScreen(), 'signin-keyboard-large-text',
        const Size(360, 800), textScale: 1.5, keyboardHeight: 300);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in').hitTestable(), findsOneWidget);
  });

  testWidgets('settings supports large text', (tester) async {
    await render(tester, SettingsScreen(workspaceLoader: () async => null),
        'settings-large-text', const Size(360, 800), textScale: 1.5);
  });
}

/// Isolated presentation fixture. No account, database or network is used.
class _ComponentPreview extends StatelessWidget {
  const _ComponentPreview();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: EnterprisePage(
          title: 'Visual review',
          subtitle: 'Design-system fixture: form controls, metrics and empty states.',
          children: [
            const SizedBox(
              height: 156,
              child: Row(children: [
                Expanded(child: StatCard(label: 'Suppliers', value: 0,
                    icon: Icons.storefront_outlined, color: AppColors.primary)),
                SizedBox(width: 12),
                Expanded(child: StatCard(label: 'Shortlisted', value: 0,
                    icon: Icons.star_outline, color: AppColors.teal)),
              ]),
            ),
            const SizedBox(height: 16),
            SectionPanel(
              title: 'Supplier details',
              subtitle: 'Keep key information clear and easy to scan.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const TextField(decoration: InputDecoration(
                    labelText: 'Company name', hintText: 'Enter supplier name')),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(label: const Text('All suppliers'), selected: true, onSelected: (_) {}),
                  ChoiceChip(label: const Text('Shortlisted'), selected: false, onSelected: (_) {}),
                  const InfoChip(label: 'Saved on this device', icon: Icons.check_circle_outline,
                      color: AppColors.teal),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add),
                    label: const Text('Add supplier')),
              ]),
            ),
            const SizedBox(height: 16),
            const EmptyState(icon: Icons.inventory_2_outlined, title: 'No products yet',
                message: 'Add product details after your first supplier conversation.'),
          ],
        ),
      );
}
