/// Conservative OCR suggestions. Users must review these before capture.
class BusinessCardParser {
  static Map<String, String> parse(String text) {
    final result = <String, String>{};
    final unlabelled = <String>[];
    const labels = <String, String>{
      'company': 'name', 'company name': 'name', 'supplier': 'name',
      'supplier name': 'name', 'organization': 'name', 'organisation': 'name',
      'contact': 'person', 'contact name': 'person',
      'contact person': 'person', 'person': 'person',
      'name': 'person', 'email': 'email', 'e-mail': 'email',
      'phone': 'phone', 'mobile': 'phone', 'tel': 'phone',
      'telephone': 'phone', 'wechat': 'wechat', 'we chat': 'wechat',
      'booth': 'booth', 'booth no': 'booth', 'booth number': 'booth',
      'hall': 'hall', 'country': 'country',
      'designation': 'role', 'title': 'role', 'position': 'role',
      'job title': 'role', 'department': 'department',
      'legal name': 'legalName', 'registered company name': 'legalName',
      'local company name': 'localName', 'brand': 'brandNames',
      'business type': 'supplierType', 'products': 'productsServices',
      'services': 'productsServices', 'established': 'yearEstablished',
      'company email': 'companyEmails', 'office phone': 'companyPhones',
      'company fax': 'companyFax', 'warehouse address': 'warehouseAddress',
      'city': 'city', 'province': 'province', 'state': 'province',
      'postal code': 'postalCode', 'zip code': 'postalCode',
      'registration number': 'registrationNumber', 'vat': 'taxNumber',
      'tax number': 'taxNumber', 'export license': 'exportLicense',
      'certifications': 'certifications', 'export markets': 'exportMarkets',
      'direct line': 'directLine', 'extension': 'directLine',
      'preferred language': 'language',
      'address': 'address', 'office': 'address', 'factory address': 'factoryAddress',
      'website': 'websites', 'web': 'websites', 'url': 'websites',
      'whatsapp': 'whatsapp', 'fax': 'fax',
      'linkedin': 'social', 'facebook': 'social', 'instagram': 'social',
      '\u516c\u53f8': 'name', '\u516c\u53f8\u540d\u79f0': 'name',
      '\u59d3\u540d': 'person', '\u8054\u7cfb\u4eba': 'person',
      '\u804c\u4f4d': 'role', '\u804c\u52a1': 'role',
      '\u7535\u8bdd': 'phone', '\u624b\u673a': 'phone',
      '\u90ae\u7bb1': 'email', '\u7535\u5b50\u90ae\u4ef6': 'email',
      '\u5fae\u4fe1': 'wechat', '\u7f51\u5740': 'websites',
      '\u5730\u5740': 'address', '\u4f20\u771f': 'fax',
      '\u5c55\u4f4d': 'booth', '\u5c55\u9986': 'hall',
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
    // Suggest an unlabelled Latin-script name only beside a known company.
    // Multiple candidates, job titles, and address-like lines stay manual.
    // Explicit contact labels always take precedence over this heuristic.
    final company = result['name'];
    if (!result.containsKey('person') && company != null) {
      final lines = text.split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
      final nameShape = RegExp(
        r"^[A-Z][a-z]+(?:['-][A-Z]?[a-z]+)*(?:\s+[A-Z][a-z]+(?:['-][A-Z]?[a-z]+)*){1,3}$",
      );
      final nonPerson = RegExp(
        r'\b(test card|not a real|street|road|avenue|building|district|city|province|country|floor|suite|room|office|park|industrial|supplies|trading|industries|technology|technologies|manufacturing|limited|ltd|inc|corporation|company|co|group|international|export|import|sales|marketing|manager|director|engineer|president|founder|executive|representative|department|service|services|contact|booth|hall)\b',
        caseSensitive: false,
      );
      final candidates = <String>{};
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (!unlabelled.contains(line) || line == company ||
            !nameShape.hasMatch(line) || nonPerson.hasMatch(line)) {
          continue;
        }
        bool isCompanyLine(String value) => value == company ||
            value.split(RegExp(r'[:\uFF1A]')).last.trim() == company;
        if ((index > 0 && isCompanyLine(lines[index - 1])) ||
            (index + 1 < lines.length && isCompanyLine(lines[index + 1]))) {
          candidates.add(line);
        }
      }
      if (candidates.length == 1) result['person'] = candidates.single;
    }
    return result;
  }

  /// All candidates are retained; review chooses the primary values.
  static Map<String, List<String>> candidates(String text) {
    final values = <String, List<String>>{};
    void add(String key, String value) {
      final clean = value.trim();
      if (clean.isEmpty) return;
      final list = values.putIfAbsent(key, () => []);
      if (!list.any((item) => item.toLowerCase() == clean.toLowerCase())) {
        list.add(clean);
      }
    }
    for (final entry in parse(text).entries) { add(entry.key, entry.value); }
    final emailPattern = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
    final websitePattern = RegExp(
      r'(?<![@\w.])(?:https?://|www\.)[^\s<>]+|(?<![@\w.])(?:[a-z0-9-]+\.)+(?:com|cn|net|org|io|co|hk|biz|in|ae)(?:/[^\s<>]*)?',
      caseSensitive: false,
    );
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      if (line.contains(RegExp(r'[:\uFF1A]'))) {
        for (final entry in parse(line).entries) { add(entry.key, entry.value); }
      }
      for (final match in emailPattern.allMatches(line)) { add('email', match.group(0)!); }
      for (final match in websitePattern.allMatches(line)) {
        add('websites', match.group(0)!.replaceAll(RegExp(r'[.,;]+$'), ''));
      }
      if (!RegExp(r'\b(fax|booth|hall|postal|zip)\b|\u4f20\u771f|\u5c55\u4f4d', caseSensitive: false).hasMatch(line)) {
        for (final match in RegExp(r'\+?\d[\d ()-]{5,}\d').allMatches(line)) {
          final value = match.group(0)!;
          final digits = value.replaceAll(RegExp(r'\D'), '');
          if (digits.length >= 7 && digits.length <= 15) add('phone', value);
        }
      }
      if (!line.contains(RegExp(r'[:\uFF1A@]')) &&
          RegExp(r'\b(manager|director|engineer|president|founder|executive)\b', caseSensitive: false).hasMatch(line) && line.length < 85) {
        add('role', line);
      }
    }
    return values;
  }
}
