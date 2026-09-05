import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app.dart';
import '../theme/app_theme.dart';
import '../data/team_workspace_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return Supabase.instance.client.auth.currentSession == null
              ? const SignInScreen()
              : ValueListenableBuilder<int>(
                  valueListenable: TeamWorkspaceService.changes,
                  builder: (context, revision, _) => CantonFairApp(
                    key: ValueKey('${Supabase.instance.client.auth.currentUser!.id}:$revision'),
                  ),
                );
        },
      );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await Supabase.instance.client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (mounted) {
          setState(() => _error =
              'Account created. You can now sign in with your email and password.');
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _identityPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.business_center_outlined, color: Colors.white, size: 24)),
        const SizedBox(width: 14),
        const Text('CANTON FAIR', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.primary)),
      ]),
      const SizedBox(height: 28),
      Text('Better conversations.\nClearer buying decisions.',
        style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 14),
      const Text('Your suppliers, products, and next steps.\nOne organized sourcing workspace.',
        style: TextStyle(color: AppColors.muted, height: 1.6)),
    ],
  );

  Widget _signInForm() => Card(child: Padding(
    padding: const EdgeInsets.all(24),
    child: AutofillGroup(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_creating ? 'Create your account' : 'Welcome back',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(_creating ? 'Set up your sourcing workspace.' : 'Sign in to continue to your workspace.',
            style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 28),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Work email', hintText: 'you@company.com',
            prefixIcon: Icon(Icons.alternate_email_rounded)),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password, obscureText: true, enabled: !_busy,
          textInputAction: TextInputAction.done,
          autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) { if (!_busy) _submit(); },
          decoration: InputDecoration(
            labelText: 'Password', helperText: _creating ? 'Use at least 6 characters' : null,
            prefixIcon: const Icon(Icons.lock_outline_rounded)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF0EF), borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)))),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_creating ? 'Create account' : 'Sign in'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => setState(() { _creating = !_creating; _error = null; }),
          child: Text(_creating ? 'Already registered? Sign in' : 'New here? Create an account',
              textAlign: TextAlign.center),
        ),
      ],
    )),
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFE8EFED), AppColors.surface, Color(0xFFEDF1F5)])),
      child: SafeArea(child: LayoutBuilder(builder: (context, constraints) =>
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity)),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: constraints.maxWidth >= 800
                  ? Row(children: [
                      Expanded(child: _identityPanel()),
                      const SizedBox(width: 64),
                      Expanded(child: _signInForm()),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _identityPanel(),
                      const SizedBox(height: 28),
                      _signInForm(),
                    ]),
            )),
          ),
        ),
      )),
    ),
  );
}
