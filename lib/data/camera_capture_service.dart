import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CameraCaptureSession {
  CameraCaptureSession(this.id);

  final int id;
  final elapsed = Stopwatch()..start();
  bool completed = false;
}

/// A bounded exception for the external camera, never for gallery/file pickers.
class CameraCaptureService {
  static const grace = Duration(seconds: 60);
  static const _channel = MethodChannel('canton_fair_crm/camera_lock');
  static final changes = ValueNotifier<int>(0);
  static CameraCaptureSession? active;
  static int _sequence = 0;

  static Future<T> capture<T>(Future<T> Function() pick) async {
    if (active != null) throw StateError('A camera capture is already open.');
    final session = CameraCaptureSession(++_sequence);
    active = session;
    changes.value++;
    try {
      try {
        await _channel.invokeMethod<void>('begin', session.id);
      } on PlatformException catch (_) {
        // Capture remains available; unavailable guards fail closed on return.
      } on MissingPluginException catch (_) {
        // Other platforms keep the normal app lock.
      }
      return await pick();
    } finally {
      session.completed = true;
      active = null;
      changes.value++;
    }
  }

  static Future<bool> canReturn(CameraCaptureSession session) async {
    if (!session.completed || session.elapsed.elapsed >= grace) return false;
    try {
      return await _channel.invokeMethod<bool>('finish', session.id) == true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
