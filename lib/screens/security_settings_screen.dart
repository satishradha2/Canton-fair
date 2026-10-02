import 'package:flutter/material.dart';
import '../data/app_lock_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _service = AppLockService();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _available = false, _enabled = false, _locked = false, _busy = true;
  String? _message;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final available = await _service.canUseBiometrics;
      final enabled = await _service.biometricLoginEnabled;
      final locked = await _service.isEnabled;
      if (mounted) setState(() { _available = available; _enabled = enabled; _locked = locked; _busy = false; });
    } catch (_) { if (mounted) setState(() { _busy = false; _message = 'Could not read security settings. Please try again.'; }); }
  }
  Future<void> _toggle(bool enabled) async {
    setState(() { _busy = true; _message = null; });
    try {
      if (enabled) {
        if (!await _service.enableBiometricLogin()) throw StateError('Confirm your fingerprint or face to enable biometric sign-in.');
      } else { await _service.disableBiometricLogin(); }
      if (mounted) setState(() => _message = enabled ? 'Biometric sign-in enabled for your account on this device.' : 'Biometric sign-in disabled.');
    } catch (error) { if (mounted) setState(() => _message = '$error'); }
    finally { if (mounted) await _load(); }
  }
  Future<void> _setPin() async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(_pin.text) || _pin.text != _confirm.text) {
      setState(() => _message = 'Enter matching PINs with 4 to 8 digits.'); return;
    }
    setState(() => _busy = true);
    try {
      await _service.setPin(_pin.text);
      _pin.clear(); _confirm.clear();
      if (mounted) setState(() => _message = 'App lock enabled. PIN or biometrics will protect the app when it is reopened.');
    } catch (_) { if (mounted) setState(() => _message = 'Could not save the PIN. Try again.'); }
    finally { if (mounted) await _load(); }
  }
  Future<void> _disableLock() async {
    setState(() => _busy = true);
    try {
      if (!await _service.verifyPin(_pin.text)) throw StateError('Enter your current PIN to disable app lock.');
      await _service.disable(); _pin.clear(); _confirm.clear();
      if (mounted) setState(() => _message = 'App lock disabled.');
    } catch (error) { if (mounted) setState(() => _message = '$error'); }
    finally { if (mounted) await _load(); }
  }
  @override
  void dispose() { _pin.dispose(); _confirm.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Security & sign-in')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.fingerprint, size: 48), const SizedBox(height: 16),
        Text('Biometric sign-in', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Sign in with your password first, then enable fingerprint or face unlock for the saved session on this device. Your password is not stored for biometric sign-in.'),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Use fingerprint / face'), value: _enabled,
          onChanged: _busy || (!_available && !_enabled) ? null : _toggle),
        if (!_available && !_busy) const Text('Set up a fingerprint or face in your phone settings. Biometrics require a supported device.'),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('App lock ${_locked ? '(enabled)' : '(optional)'}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Add a PIN to protect the app when the phone locks or the app goes into the background. Supported biometrics are available on the unlock screen.'),
        const SizedBox(height: 16),
        TextField(controller: _pin, enabled: !_busy, obscureText: true, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _locked ? 'Current PIN (to disable) / new PIN (to replace)' : 'New PIN (4 to 8 digits)')),
        const SizedBox(height: 12), TextField(controller: _confirm, enabled: !_busy, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm new PIN')),
        const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : _setPin, child: Text(_locked ? 'Replace PIN' : 'Enable app lock')),
        if (_locked) TextButton(onPressed: _busy ? null : _disableLock, child: const Text('Disable app lock using current PIN')),
      ]))),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
    ]));
}
