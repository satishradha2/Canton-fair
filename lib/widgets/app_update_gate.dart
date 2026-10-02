import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/update_service.dart';

/// Non-blocking release checks; no background downloads or forced installs.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  static void check(BuildContext context) {
    context.findAncestorStateOfType<_AppUpdateGateState>()?._check(manual: true);
  }

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _checking = false;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool manual = false}) async {
    if (!mounted || _checking) return;
    if (kIsWeb || !Platform.isAndroid) {
      if (manual) _message('APK updates are available on Android only.');
      return;
    }
    if (!manual && _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 10)) {
      return;
    }
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final update = await UpdateService().checkLatest();
      if (!mounted) return;
      if (update.updateAvailable && update.apkUrl != null) {
        await showDialog<void>(context: context, barrierDismissible: false,
          builder: (_) => _UpdateDialog(update: update));
      } else if (manual) {
        _message(update.updateAvailable
            ? 'A new release exists, but its APK is not available yet. Try again later.'
            : 'App is up to date (${update.currentVersion}).');
      }
    } catch (error) {
      if (mounted && manual) _message('Update check failed: $error');
    } finally {
      _checking = false;
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});
  final AppUpdateInfo update;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() { _downloading = true; _error = null; _progress = null; });
    try {
      await UpdateService().downloadAndInstall(widget.update,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress.fraction?.clamp(0.0, 1.0));
        });
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _downloading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_downloading,
    child: AlertDialog(
      title: const Text('Fair Expert update available'),
      content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Installed: ${widget.update.currentVersion}\nNew release: ${widget.update.latestVersion}'),
        const SizedBox(height: 12),
        const Text('Your saved contacts and products will be kept. Android will ask you to confirm installation.'),
        if (_downloading) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 8),
          Text(_progress == null ? 'Downloading update...' :
            _progress! >= 1 ? 'Download received. Preparing installation...' :
            'Downloading ${(_progress! * 100).floor()}%'),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
      actions: [
        TextButton(onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Later')),
        FilledButton(onPressed: _downloading ? null : _install,
          child: Text(_error == null ? 'Download & install' : 'Retry')),
      ],
    ),
  );
}
