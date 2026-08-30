import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../app.dart';
import '../data/auth_region_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _region = AuthRegionService();
  String? _choice;
  @override
  void initState() {
    super.initState();
    _region.load().then((value) {
      if (mounted) setState(() => _choice = value);
    });
  }

  Future<void> _setRegion(String value) async {
    await _region.save(value);
    if (mounted) setState(() => _choice = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_choice == null) return RegionChoiceScreen(onSelected: _setRegion);
    if (_choice == 'china')
      return ChinaSignInScreen(onChangeRegion: () => _setRegion('other'));
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        return snapshot.hasData ? const CantonFairApp() : const SignInScreen();
      },
    );
  }
}

class RegionChoiceScreen extends StatelessWidget {
  final Future<void> Function(String) onSelected;
  const RegionChoiceScreen({super.key, required this.onSelected});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.public, size: 48),
                    const SizedBox(height: 16),
                    Text('Where are you signing in from?',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                        'This selects the most reliable and secure sign-in method.'),
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: () => onSelected('china'),
                            child: const Text('Mainland China'))),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                            onPressed: () => onSelected('other'),
                            child: const Text('Other country'))),
                  ])))));
}

class ChinaSignInScreen extends StatelessWidget {
  final VoidCallback onChangeRegion;
  const ChinaSignInScreen({super.key, required this.onChangeRegion});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text('China secure sign-in',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                        'This route uses the planned Keycloak JWT service instead of Google-based authentication.'),
                    const SizedBox(height: 16),
                    const Text(
                        'Keycloak connection details are still required.'),
                    TextButton(
                        onPressed: onChangeRegion,
                        child: const Text('Use other-country sign-in')),
                  ])))));
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
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Google Sign-In is unavailable on this device or network. Use email and password instead.');
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

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.apartment, size: 48),
                        const SizedBox(height: 16),
                        Text(_creating ? 'Create team account' : 'Sign in',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                const InputDecoration(labelText: 'Email')),
                        TextField(
                            controller: _password,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'Password (minimum 6 characters)')),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_error!,
                                  style: const TextStyle(color: Colors.red))),
                        const SizedBox(height: 16),
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                child: Text(
                                    _creating ? 'Create account' : 'Sign in'))),
                        OutlinedButton.icon(
                            onPressed: _busy ? null : _signInWithGoogle,
                            icon: const Icon(Icons.g_mobiledata),
                            label:
                                const Text('Continue with Google (optional)')),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _creating = !_creating),
                            child: Text(_creating
                                ? 'Already have an account? Sign in'
                                : 'Create a new account')),
                      ]))))));
}
