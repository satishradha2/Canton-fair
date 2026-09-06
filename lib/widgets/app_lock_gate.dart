import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_lock_service.dart';
import '../data/camera_capture_service.dart';
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
  CameraCaptureSession? _cameraReturn;
  Timer? _cameraTimeout;
  bool _checkingCamera = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.changes.addListener(_settingsChanged);
    CameraCaptureService.changes.addListener(_cameraChanged);
    _refresh();
  }

  void _settingsChanged() {
    _clearCameraReturn();
    _refresh();
  }

  void _clearCameraReturn() {
    _cameraTimeout?.cancel();
    _cameraTimeout = null;
    _cameraReturn = null;
  }

  void _cameraChanged() {
    _tryCameraReturn();
  }

  Future<void> _tryCameraReturn() async {
    final session = _cameraReturn;
    if (session == null || !session.completed || !_resumed ||
        _checkingCamera) {
      return;
    }
    _checkingCamera = true;
    final allowed = await CameraCaptureService.canReturn(session);
    _checkingCamera = false;
    if (!mounted || _cameraReturn != session) return;
    setState(() {
      _clearCameraReturn();
      if (allowed && _resumed &&
          session.elapsed.elapsed < CameraCaptureService.grace) {
        _locked = false;
      }
    });
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
    _resumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && _enabled) {
      final session = CameraCaptureService.active;
      final eligible = !_locked && session != null &&
          session.elapsed.elapsed < CameraCaptureService.grace;
      setState(() {
        _clearCameraReturn();
        _locked = true;
        if (eligible) {
          _cameraReturn = session;
          _cameraTimeout = Timer(
            CameraCaptureService.grace - session.elapsed.elapsed,
            () {
              if (mounted) setState(_clearCameraReturn);
            },
          );
        }
      });
    }
    if (_resumed) _tryCameraReturn();
  }

  @override
  void dispose() {
    AppLockService.changes.removeListener(_settingsChanged);
    CameraCaptureService.changes.removeListener(_cameraChanged);
    _clearCameraReturn();
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
        if (!_ready || (_locked && _cameraReturn != null))
          const Scaffold(body: Center(child: CircularProgressIndicator()))
        else if (_locked)
          AppLockScreen(
            onUnlocked: () => setState(() => _locked = false),
          ),
      ],
    );
  }
}
