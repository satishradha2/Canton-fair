import 'package:canton_fair_crm/data/business_card_parser.dart';
import 'package:canton_fair_crm/data/phone_number_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cordeliaCard = '''
CORDELIA
CONTAINER SHIPPING LINE
Prasanth Punnakkal
Asst. Manager - Sales
Cordelia Container Shipping Line LLC
#103, 1st Floor, Building 04, Bay Square, Al Asayel Street,
Business Bay, Dubai - UAE
971 4 596 3807   +971 56 685 5303
prasanth@cordelialine.com   www.cordelialine.com
''';

  test('retains every phone, email, website, address and country candidate',
      () {
    final values = BusinessCardParser.candidates(cordeliaCard);

    expect(values['phone'], hasLength(2));
    expect(values['email'], contains('prasanth@cordelialine.com'));
    expect(values['websites'], contains('www.cordelialine.com'));
    expect(values['country'], contains('United Arab Emirates'));
    expect(values['address'], isNotEmpty);
    expect(values['name'], contains('Cordelia Container Shipping Line LLC'));
  });

  test('adds UAE prefix and does not duplicate an existing country code', () {
    expect(
      PhoneNumberNormalizer.normalize(
        '971 4 596 3807',
        country: 'United Arab Emirates',
      ),
      '+97145963807',
    );
    expect(
      PhoneNumberNormalizer.normalize(
        '+971 56 685 5303',
        country: 'UAE',
      ),
      '+971566855303',
    );
    expect(
      PhoneNumberNormalizer.normalize(
        '04 596 3807',
        country: 'Dubai, UAE',
      ),
      '+97145963807',
    );
  });

  test('normalizes and de-duplicates multiple phone values', () {
    expect(
      PhoneNumberNormalizer.normalizeList(
        '971 4 596 3807\n+971 56 685 5303\n+971 56 685 5303',
        country: 'UAE',
      ),
      '+97145963807\n+971566855303',
    );
  });
}
