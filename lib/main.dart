import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'data/reminder_service.dart';
import 'data/team_workspace_service.dart';
import 'data/appearance_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
        'Supabase is not configured. Build with SUPABASE_URL and SUPABASE_ANON_KEY.');
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
  await ReminderService.initialize();
  runApp(const CantonFairRoot());
}

class CantonFairRoot extends StatefulWidget {
  const CantonFairRoot({super.key});

  @override
  State<CantonFairRoot> createState() => _CantonFairRootState();
}

class _CantonFairRootState extends State<CantonFairRoot> {
  @override
  void initState() {
    super.initState();
    AppearanceService().load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: AppearanceService.changes,
    builder: (context, themeMode, _) => MaterialApp(
      title: 'Canton Fair CRM',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode,
      home: const AuthGate(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: AppLockGate(
          child: ValueListenableBuilder<bool>(
        valueListenable: TeamWorkspaceService.busy,
        builder: (context, busy, _) => PopScope(
          canPop: !busy,
          child: Stack(children: [
            if (child != null) child,
            if (busy) ...[
              const ModalBarrier(dismissible: false, color: Color(0x55000000)),
              const Center(child: CircularProgressIndicator()),
            ],
          ]),
        ),
          ),
        ),
      ),
    ),
  );
}
