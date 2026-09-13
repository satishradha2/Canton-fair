class PhoneNumberNormalizer {
  const PhoneNumberNormalizer._();

  static const _countryCodes = <String, String>{
    'ae': '971',
    'uae': '971',
    'united arab emirates': '971',
    'dubai': '971',
    'cn': '86',
    'china': '86',
    'prc': '86',
    'hk': '852',
    'hong kong': '852',
    'in': '91',
    'india': '91',
    'us': '1',
    'usa': '1',
    'united states': '1',
    'united states of america': '1',
    'ca': '1',
    'canada': '1',
    'gb': '44',
    'uk': '44',
    'united kingdom': '44',
    'england': '44',
    'de': '49',
    'germany': '49',
    'fr': '33',
    'france': '33',
    'it': '39',
    'italy': '39',
    'es': '34',
    'spain': '34',
    'tr': '90',
    'turkey': '90',
    'turkiye': '90',
    'sa': '966',
    'saudi arabia': '966',
    'qa': '974',
    'qatar': '974',
    'kw': '965',
    'kuwait': '965',
    'om': '968',
    'oman': '968',
    'bh': '973',
    'bahrain': '973',
    'sg': '65',
    'singapore': '65',
    'my': '60',
    'malaysia': '60',
    'id': '62',
    'indonesia': '62',
    'th': '66',
    'thailand': '66',
    'vn': '84',
    'vietnam': '84',
    'jp': '81',
    'japan': '81',
    'kr': '82',
    'south korea': '82',
    'korea': '82',
    'au': '61',
    'australia': '61',
    'nz': '64',
    'new zealand': '64',
    'br': '55',
    'brazil': '55',
    'mx': '52',
    'mexico': '52',
    'za': '27',
    'south africa': '27',
    'eg': '20',
    'egypt': '20',
    'pk': '92',
    'pakistan': '92',
    'bd': '880',
    'bangladesh': '880',
    'lk': '94',
    'sri lanka': '94',
    'ru': '7',
    'russia': '7',
    'nl': '31',
    'netherlands': '31',
    'be': '32',
    'belgium': '32',
    'ch': '41',
    'switzerland': '41',
    'at': '43',
    'austria': '43',
    'pl': '48',
    'poland': '48',
    'se': '46',
    'sweden': '46',
    'no': '47',
    'norway': '47',
    'dk': '45',
    'denmark': '45',
  };

  static String? callingCode(String country) {
    final clean = country
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    if (_countryCodes.containsKey(clean)) return _countryCodes[clean];
    for (final entry in _countryCodes.entries) {
      if (clean.contains(entry.key) && entry.key.length > 2) return entry.value;
    }
    return null;
  }

  static String normalize(String value, {required String country}) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final extension = RegExp(
          r'(?:\s*(?:ext\.?|extension|x)\s*\d+)\s*$',
          caseSensitive: false,
        ).firstMatch(raw)?.group(0) ??
        '';
    var core = extension.isEmpty
        ? raw
        : raw.substring(0, raw.length - extension.length);
    core = core.replaceAll(RegExp(r'[^0-9+]'), '');
    if (core.startsWith('00')) core = '+${core.substring(2)}';
    if (core.startsWith('+')) return '$core$extension';
    final digits = core.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return raw;
    final code = callingCode(country);
    if (code == null) return '$digits$extension';
    if (digits.startsWith(code) && digits.length > code.length + 5) {
      return '+$digits$extension';
    }
    final local = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+$code$local$extension';
  }

  static String normalizeList(String value, {required String country}) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in value.split(RegExp(r'[;\r\n]+'))) {
      final normalized = normalize(item, country: country);
      final identity = normalized.replaceAll(RegExp(r'\D'), '');
      if (identity.isNotEmpty && seen.add(identity)) result.add(normalized);
    }
    return result.join('\n');
  }

  static Map<String, String> normalizeFields(Map<String, String> fields) {
    final result = Map<String, String>.from(fields);
    final country = result['country'] ?? '';
    for (final key in const [
      'phone',
      'otherPhones',
      'companyPhones',
      'whatsapp',
      'fax',
      'companyFax',
      'directLine',
    ]) {
      final value = result[key];
      if (value != null && value.trim().isNotEmpty) {
        result[key] = normalizeList(value, country: country);
      }
    }
    return result;
  }
}
