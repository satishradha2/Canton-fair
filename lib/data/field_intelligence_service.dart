import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class CurrencySnapshot {
  const CurrencySnapshot({required this.date, required this.perEuro});

  final DateTime date;
  final Map<String, double> perEuro;

  double convert(double amount, String from, String to) {
    final source = from.toUpperCase();
    final target = to.toUpperCase();
    if (source == target) return amount;
    final sourceRate = source == 'EUR' ? 1.0 : perEuro[source];
    final targetRate = target == 'EUR' ? 1.0 : perEuro[target];
    if (sourceRate == null || targetRate == null) {
      throw StateError('No exchange rate is available for $source or $target.');
    }
    return amount / sourceRate * targetRate;
  }
}

class FieldIntelligenceService {
  const FieldIntelligenceService();

  static const _ecbRates =
      'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml';

  Future<CurrencySnapshot> latestRates() async {
    final response = await http
        .get(Uri.parse(_ecbRates))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError(
          'Exchange-rate service returned ${response.statusCode}.');
    }
    final rates = <String, double>{};
    final expression =
        RegExp(r'''currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]''');
    for (final match in expression.allMatches(response.body)) {
      final value = double.tryParse(match.group(2)!);
      if (value != null) rates[match.group(1)!] = value;
    }
    final dateMatch = RegExp(r'''time=['"](\d{4}-\d{2}-\d{2})['"]''')
        .firstMatch(response.body);
    if (rates.isEmpty || dateMatch == null) {
      throw StateError('The exchange-rate response could not be read.');
    }
    return CurrencySnapshot(
        date: DateTime.parse(dateMatch.group(1)!), perEuro: rates);
  }

  Map<String, num> containerLoad({
    required double cartonLengthCm,
    required double cartonWidthCm,
    required double cartonHeightCm,
    required double cartonWeightKg,
    required int unitsPerCarton,
    required double containerCbm,
    required double payloadKg,
    double utilization = .85,
  }) {
    if ([
          cartonLengthCm,
          cartonWidthCm,
          cartonHeightCm,
          cartonWeightKg,
          containerCbm,
          payloadKg
        ].any((value) => value <= 0) ||
        unitsPerCarton <= 0) {
      throw const FormatException(
          'All carton and container values must be positive.');
    }
    final cartonCbm = cartonLengthCm * cartonWidthCm * cartonHeightCm / 1000000;
    final byVolume = (containerCbm * utilization / cartonCbm).floor();
    final byWeight = (payloadKg / cartonWeightKg).floor();
    final cartons = math.min(byVolume, byWeight);
    return {
      'carton_cbm': cartonCbm,
      'cartons_by_volume': byVolume,
      'cartons_by_weight': byWeight,
      'recommended_cartons': cartons,
      'recommended_units': cartons * unitsPerCarton,
      'used_cbm': cartons * cartonCbm,
      'used_weight_kg': cartons * cartonWeightKg,
    };
  }

  int aqlSampleSize(int lotSize, {String level = 'II'}) {
    if (lotSize <= 0) throw const FormatException('Lot size must be positive.');
    final base = switch (lotSize) {
      <= 8 => 2,
      <= 15 => 3,
      <= 25 => 5,
      <= 50 => 8,
      <= 90 => 13,
      <= 150 => 20,
      <= 280 => 32,
      <= 500 => 50,
      <= 1200 => 80,
      <= 3200 => 125,
      <= 10000 => 200,
      <= 35000 => 315,
      <= 150000 => 500,
      <= 500000 => 800,
      _ => 1250,
    };
    final factor = switch (level) { 'I' => .63, 'III' => 1.6, _ => 1.0 };
    return math.min(lotSize, math.max(2, (base * factor).round()));
  }

  Map<String, int> defectLimits(int sampleSize,
      {double critical = 0, double major = 2.5, double minor = 4}) {
    int limit(double aql) => aql == 0 ? 0 : (sampleSize * aql / 100).floor();
    return {
      'critical': limit(critical),
      'major': limit(major),
      'minor': limit(minor),
    };
  }

  String encodeTransfer(Map<String, Object?> payload) {
    final envelope = {
      'format': 'CFC_TRANSFER',
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    final compressed = gzip.encode(utf8.encode(jsonEncode(envelope)));
    return 'CFC-XFER1:${base64UrlEncode(compressed).replaceAll('=', '')}';
  }

  Map<String, dynamic> decodeTransfer(String value) {
    if (!value.startsWith('CFC-XFER1:')) {
      throw const FormatException('This is not a Canton Fair transfer code.');
    }
    final raw = value.substring('CFC-XFER1:'.length);
    final padded = raw.padRight((raw.length + 3) ~/ 4 * 4, '=');
    final decoded =
        jsonDecode(utf8.decode(gzip.decode(base64Url.decode(padded))));
    if (decoded is! Map ||
        decoded['format'] != 'CFC_TRANSFER' ||
        decoded['version'] != 1) {
      throw const FormatException('Unsupported transfer format.');
    }
    final payload = decoded['payload'];
    if (payload is! Map) {
      throw const FormatException('Transfer payload is missing.');
    }
    return Map<String, dynamic>.from(payload);
  }

  List<T> reorderRoute<T>(
    List<T> items, {
    required String Function(T) hall,
    required String Function(T) booth,
    required int Function(T) priority,
    required bool Function(T) completed,
  }) {
    final result = [...items];
    int boothNumber(String value) =>
        int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ??
        999999;
    result.sort((a, b) {
      final complete =
          completed(a) == completed(b) ? 0 : (completed(a) ? 1 : -1);
      if (complete != 0) return complete;
      final priorityOrder = priority(b).compareTo(priority(a));
      if (priorityOrder != 0) return priorityOrder;
      final hallOrder = hall(a).compareTo(hall(b));
      if (hallOrder != 0) return hallOrder;
      return boothNumber(booth(a)).compareTo(boothNumber(booth(b)));
    });
    return result;
  }
}
