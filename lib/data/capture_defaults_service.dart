import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CaptureDefaults {
  final int? tripId;
  final String country;

  const CaptureDefaults({this.tripId, this.country = ''});
}

class CaptureDefaultsService {
  static const _tripIdKey = 'capture_default_trip_id';
  static const _countryKey = 'capture_default_country';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<CaptureDefaults> load() async {
    final tripId = int.tryParse(await _storage.read(key: _tripIdKey) ?? '');
    final country = await _storage.read(key: _countryKey) ?? '';
    return CaptureDefaults(tripId: tripId, country: country);
  }

  Future<void> save({required int tripId, required String country}) async {
    await _storage.write(key: _tripIdKey, value: '$tripId');
    await _storage.write(key: _countryKey, value: country.trim());
  }
}
