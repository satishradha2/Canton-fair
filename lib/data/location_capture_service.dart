import 'package:geolocator/geolocator.dart';

class CapturedLocation {
  final double latitude;
  final double longitude;
  final double accuracyMetres;
  final DateTime capturedAt;

  const CapturedLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.capturedAt,
  });

  Map<String, Object> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_metres': accuracyMetres,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };
}

class LocationCaptureService {
  Future<CapturedLocation> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('Location permission was not granted.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
          'Location permission is blocked. Enable it in Android app settings.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return CapturedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy,
      capturedAt: position.timestamp,
    );
  }
}
