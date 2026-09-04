import 'package:flutter/material.dart';

import '../data/app_lock_service.dart';
import '../theme/app_theme.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _service = AppLockService();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _biometricsAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
  }

  Future<void> _loadBiometrics() async {
    final available = await _service.canUseBiometrics;
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  Future<void> _unlockWithPin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final valid = await _service.verifyPin(_pin.text);
    if (!mounted) return;
    if (valid) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _busy = false;
      _error = 'Incorrect PIN. Please try again.';
      _pin.clear();
    });
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() => _busy = true);
    final valid = await _service.authenticateWithBiometrics();
    if (!mounted) return;
    if (valid) {
      widget.onUnlocked();
      return;
    }
    setState(() => _busy = false);
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  const Text('Canton Fair CRM',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Enter your PIN to continue.',
                      style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    textAlign: TextAlign.center,
                    onSubmitted: (_) => _busy ? null : _unlockWithPin(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: _error,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _unlockWithPin,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Unlock'),
                    ),
                  ),
                  if (_biometricsAvailable) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
