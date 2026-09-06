import 'package:flutter/material.dart';

import '../data/app_lock_service.dart';
import 'app_lock_screen.dart';

/// Covers the entire Navigator without disposing routes or pending captures.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final _service = AppLockService();
  bool _ready = false;
  bool _enabled = true;
  bool _locked = true;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.changes.addListener(_settingsChanged);
    _refresh();
  }

  void _settingsChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    bool enabled;
    try {
      enabled = await _service.isEnabled;
    } catch (_) {
      // A secure-storage failure must never expose the workspace.
      enabled = true;
    }
    if (!mounted || generation != _refreshGeneration) return;
    setState(() {
      _locked = enabled && (!_ready || !_enabled || _locked);
      _enabled = enabled;
      _ready = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _enabled && !_locked) {
      setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    AppLockService.changes.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final covered = !_ready || _locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the same subtree mounted even while authentication is pending.
        ExcludeFocus(
          excluding: covered,
          child: Offstage(offstage: covered, child: widget.child),
        ),
        if (!_ready)
          const Scaffold(body: Center(child: CircularProgressIndicator()))
        else if (_locked)
          AppLockScreen(
            onUnlocked: () => setState(() => _locked = false),
          ),
      ],
    );
  }
}
