/// Contact QR suggestions only. Keep the original payload so unmapped fields
/// and unsupported encodings can be reviewed instead of silently discarded.
class ContactQrParser {
  static Map<String, String> parse(String raw) {
    final result = <String, String>{'contactNotes': 'Original QR payload:\n$raw'};
    final unfolded = raw.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final vcard = unfolded.trimLeft().toUpperCase().startsWith('BEGIN:VCARD');
    final mecard = unfolded.trimLeft().toUpperCase().startsWith('MECARD:');
    if (!vcard && !mecard) return result;
    final lines = vcard ? unfolded.split(RegExp(r'\r?\n'))
        : _split(unfolded.trim().substring(7), ';');
    final emails = <String>[];
    final phones = <String>[];
    for (final line in lines) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final header = line.substring(0, colon).toUpperCase();
      // Do not misinterpret quoted-printable or binary values as contact text.
      if (header.contains('ENCODING=')) continue;
      final key = header.split(';').first.split('.').last;
      final value = _unescape(line.substring(colon + 1)).trim();
      if (value.isEmpty) continue;
      switch (key) {
        case 'FN': result['person'] = value; break;
        case 'N':
          final parts = _split(line.substring(colon + 1), vcard ? ';' : ',');
          final ordered = parts.length >= 2 ? [parts[1], parts[0], ...parts.skip(2)] : parts;
          result.putIfAbsent('person', () => ordered.map(_unescape)
              .where((part) => part.trim().isNotEmpty).join(' '));
          break;
        case 'TITLE': result['role'] = value; break;
        case 'EMAIL': if (!emails.contains(value)) emails.add(value); break;
        case 'TEL':
          final phone = value.replaceFirst(RegExp(r'^tel:', caseSensitive: false), '');
          if (!phones.contains(phone)) phones.add(phone);
          break;
        case 'URL': result['contactSocial'] = [result['contactSocial'], value]
            .whereType<String>().join('\n'); break;
        default: break;
      }
    }
    if (emails.isNotEmpty) result['email'] = emails.first;
    if (emails.length > 1) result['otherEmails'] = emails.skip(1).join('\n');
    if (phones.isNotEmpty) result['phone'] = phones.first;
    if (phones.length > 1) result['otherPhones'] = phones.skip(1).join('\n');
    return result;
  }

  static List<String> _split(String value, String delimiter) {
    final result = <String>[];
    var segment = StringBuffer();
    var escaped = false;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (character == delimiter && !escaped) {
        result.add(segment.toString()); segment = StringBuffer();
      } else { segment.write(character); }
      if (character == '\\' && !escaped) { escaped = true; }
      else { escaped = false; }
    }
    result.add(segment.toString());
    return result;
  }

  static String _unescape(String value) => value.replaceAllMapped(
      RegExp(r'\\([nN,;\\])'), (match) =>
          match[1]!.toLowerCase() == 'n' ? '\n' : match[1]!);
}
