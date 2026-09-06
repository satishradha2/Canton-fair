/// Conservative OCR suggestions. Users must review these before capture.
class BusinessCardParser {
  static Map<String, String> parse(String text) {
    final result = <String, String>{};
    final unlabelled = <String>[];
    const labels = <String, String>{
      'company': 'name', 'company name': 'name', 'supplier': 'name',
      'supplier name': 'name', 'organization': 'name', 'organisation': 'name',
      'contact': 'person', 'contact name': 'person', 'person': 'person',
      'name': 'person', 'email': 'email', 'e-mail': 'email',
      'phone': 'phone', 'mobile': 'phone', 'tel': 'phone',
      'telephone': 'phone', 'wechat': 'wechat', 'we chat': 'wechat',
      'booth': 'booth', 'booth no': 'booth', 'booth number': 'booth',
      'hall': 'hall', 'country': 'country',
    };
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(RegExp(r'[:\uFF1A]'));
      if (separator >= 0) {
        final label = line.substring(0, separator).toLowerCase()
            .replaceAll(RegExp(r'[.#]'), '').trim();
        final field = labels[label];
        final value = line.substring(separator + 1).trim();
        if (field != null && value.isNotEmpty) result[field] = value;
      } else {
        unlabelled.add(line);
      }
    }
    final email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
        .firstMatch(text)?.group(0);
    if (email != null) result.putIfAbsent('email', () => email);
    // Do not mistake a contact name, disclaimer, or address for a company.
    if (!result.containsKey('name')) {
      final candidates = unlabelled.where((line) =>
          !line.contains('@') &&
          !RegExp(r'\b(test card|not a real|street|road|avenue|www)\b',
              caseSensitive: false).hasMatch(line) &&
          RegExp(r'\b(supplies|trading|industries|industrial|technology|technologies|manufacturing|limited|ltd|inc|corporation|company|co)\b',
              caseSensitive: false).hasMatch(line)).toList();
      if (candidates.length == 1) result['name'] = candidates.single;
    }
    return result;
  }
}
