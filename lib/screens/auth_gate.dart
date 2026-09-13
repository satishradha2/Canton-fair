import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app.dart';
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
          if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
            return const UpdatePasswordScreen();
          }
          return Supabase.instance.client.auth.currentSession == null
              ? const SignInScreen()
              : ValueListenableBuilder<int>(
                  valueListenable: TeamWorkspaceService.changes,
                  builder: (context, revision, _) => CantonFairApp(
                    key: ValueKey(
                        '${Supabase.instance.client.auth.currentUser!.id}:$revision'),
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

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your work email first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'cantonfair://auth-callback',
      );
      if (mounted) {
        setState(() => _error =
            'Password recovery email sent. Open the link in your inbox.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send recovery email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
              'Account created. Check your email if confirmation is required, then sign in.');
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

  Widget _identityPanel() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.business_center_outlined,
                  color: colors.onPrimaryContainer, size: 24)),
          const SizedBox(width: 14),
          Text('CANTON FAIR',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: colors.primary)),
        ]),
        const SizedBox(height: 28),
        Text('Better conversations.\nClearer buying decisions.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 14),
        Text(
            'Your suppliers, products, and next steps.\nOne organized sourcing workspace.',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6)),
      ],
    );
  }

  Widget _signInForm() => Card(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_creating ? 'Create your account' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
                _creating
                    ? 'Set up your sourcing workspace.'
                    : 'Sign in to continue to your workspace.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: 'Work email',
                  hintText: 'you@company.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _creating ? AutofillHints.newPassword : AutofillHints.password
              ],
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
              decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _creating ? 'Use at least 6 characters' : null,
                  prefixIcon: const Icon(Icons.lock_outline_rounded)),
            ),
            if (!_creating)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                  liveRegion: true,
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 13,
                          )))),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_creating ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _creating = !_creating;
                        _error = null;
                      }),
              child: Text(
                  _creating
                      ? 'Already registered? Sign in'
                      : 'New here? Create an account',
                  textAlign: TextAlign.center),
            ),
          ],
        )),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
              child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48)
                        .clamp(0.0, double.infinity)),
                child: Center(
                    child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: constraints.maxWidth >= 800
                      ? Row(children: [
                          Expanded(child: _identityPanel()),
                          const SizedBox(width: 64),
                          Expanded(child: _signInForm()),
                        ])
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _update() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _password.text));
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Choose a new password',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration:
                              const InputDecoration(labelText: 'New password'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmation,
                          obscureText: true,
                          onSubmitted: (_) => _busy ? null : _update(),
                          decoration: const InputDecoration(
                              labelText: 'Confirm new password'),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : _update,
                          child:
                              Text(_busy ? 'Updating...' : 'Update password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
