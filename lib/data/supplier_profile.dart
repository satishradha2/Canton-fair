import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'business_card_capture.dart';
import 'database.dart';
import 'team_workspace_service.dart';

class SupplierProfile {
  static const companyFields = <String, String>{
    'name': 'Supplier / company name', 'legalName': 'Legal company name',
    'localName': 'Company name in local language', 'brandNames': 'Brands / trading names',
    'supplierType': 'Manufacturer / trader / distributor',
    'category': 'Product category', 'productsServices': 'Products and services',
    'yearEstablished': 'Year established', 'websites': 'Websites (one per line)',
    'companyEmails': 'Company emails (one per line)', 'companyPhones': 'Office phones (one per line)',
    'companyFax': 'Company fax', 'address': 'Full business addresses',
    'factoryAddress': 'Factory address', 'warehouseAddress': 'Warehouse address',
    'city': 'City', 'province': 'Province / state', 'postalCode': 'Postal code',
    'country': 'Country', 'registrationNumber': 'Business registration number',
    'taxNumber': 'Tax / VAT number', 'exportLicense': 'Export licence reference',
    'certifications': 'Certifications shown / reported', 'exportMarkets': 'Export markets',
    'booth': 'Booth', 'hall': 'Hall', 'social': 'Company social profiles',
    'notes': 'Supplier notes', 'other': 'Additional details / custom field notes',
  };
  static const contactFields = <String, String>{
    'person': 'Contact name', 'localPerson': 'Contact name in local language',
    'role': 'Designation / job title', 'department': 'Department',
    'email': 'Primary email', 'otherEmails': 'Other emails (one per line)',
    'phone': 'Primary phone', 'otherPhones': 'Other phones (one per line)',
    'whatsapp': 'WhatsApp', 'wechat': 'WeChat', 'fax': 'Contact fax',
    'directLine': 'Direct line / extension', 'contactSocial': 'Contact social profiles',
    'language': 'Preferred language', 'contactNotes': 'Contact notes',
  };
  static const multiline = {
    'brandNames', 'productsServices', 'websites', 'companyEmails', 'companyPhones',
    'address', 'factoryAddress', 'warehouseAddress', 'certifications', 'exportMarkets',
    'social', 'notes', 'other', 'otherEmails', 'otherPhones', 'contactSocial', 'contactNotes',
  };

  static Map<String, dynamic> object(String value) =>
      Map<String, dynamic>.from(jsonDecode(value) as Map);

  static Map<String, String> companySubset(Map<String, String> fields) => {
    for (final key in companyFields.keys) if (fields.containsKey(key)) key: fields[key]!,
  };
  static Map<String, String> contactSubset(Map<String, String> fields) => {
    for (final key in contactFields.keys) if (fields.containsKey(key)) key: fields[key]!,
  };

  static Map<String, String> company(Exhibitor supplier) {
    final capture = object(supplier.fieldCaptureJson);
    final archive = capture['business_card'] as Map? ?? {};
    final legacy = archive['fields'] as Map? ?? {};
    final saved = capture['supplier_details'] as Map? ?? {};
    return {
      for (final key in companyFields.keys)
        key: (saved[key] ?? legacy[key] ?? '').toString(),
      'name': supplier.name, 'booth': supplier.booth, 'hall': supplier.hall,
      'country': supplier.country, 'category': supplier.category,
      'notes': supplier.contactCompanyNotes,
    };
  }

  static Map<String, String> contact(Contact? contact) {
    if (contact == null) return {for (final key in contactFields.keys) key: ''};
    final profile = object(contact.profileJson);
    final details = profile['details'] as Map? ?? {};
    return {
      for (final key in contactFields.keys) key: (details[key] ?? '').toString(),
      'person': contact.name, 'role': contact.designation, 'email': contact.email,
      'phone': contact.phone, 'wechat': contact.wechat, 'whatsapp': contact.whatsapp,
      'language': (profile['language'] ?? details['language'] ?? '').toString(),
    };
  }

  static List<Map<String, dynamic>> cards(Exhibitor supplier) {
    final capture = object(supplier.fieldCaptureJson);
    final cards = <String, Map<String, dynamic>>{};
    for (final item in capture['business_cards'] as List? ?? []) {
      final data = Map<String, dynamic>.from(item as Map);
      cards[data['id'].toString()] = data;
    }
    if (capture['business_card'] is Map) {
      final data = Map<String, dynamic>.from(capture['business_card'] as Map);
      cards[data['id'].toString()] = data;
    }
    return cards.values.toList();
  }

  static Future<Exhibitor> save({
    required Exhibitor original, required String scope,
    required Map<String, String> values, Contact? originalContact,
    required bool saveContact, BusinessCardCapture? card,
  }) async {
    return TeamWorkspaceService.exclusive(() async {
      if (await TeamWorkspaceService().scopeKey() != scope ||
          (card != null && card.scope != scope)) {
        throw StateError('Workspace changed. Reopen the supplier in its original workspace.');
      }
      final database = await TradeDatabase.instance.database;
      final saved = await database.transaction<Exhibitor>((txn) async {
        final rows = await txn.query('exhibitors', where: 'id = ?', whereArgs: [original.id]);
        if (rows.isEmpty) throw StateError('This supplier was removed.');
        final row = rows.single;
        final before = original.toMap();
        for (final key in ['name', 'booth', 'hall', 'country', 'category', 'notes', 'field_capture_json']) {
          if (row[key] != before[key]) throw StateError('Supplier details changed elsewhere. Reopen and review before saving.');
        }
        final capture = object(row['field_capture_json'] as String? ?? '{}');
        capture['supplier_details'] = {
          ...Map<String, dynamic>.from(capture['supplier_details'] as Map? ?? {}),
          ...companySubset(values),
        };
        if (card != null) {
          final archive = card.archive();
          final history = cards(Exhibitor.fromMap(row)).where((item) => item['id'] != card.id).toList();
          capture['business_cards'] = [...history, archive];
          capture['business_card'] = archive;
          for (final side in card.sides.keys) {
            final files = {
              'Business card $side | ${card.id}': card.imagePath(side),
              if (card.readingPath(side) != card.imagePath(side))
                'Business card $side corrected | ${card.id}': card.readingPath(side),
            };
            for (final entry in files.entries) {
              if (!await File(entry.value).exists()) throw StateError('Card image missing. Recapture it before saving.');
              final linked = await txn.query('attachments', where: 'path = ?', whereArgs: [entry.value]);
              if (linked.any((item) => item['owner_type'] != 'exhibitor' || item['owner_id'] != original.id)) {
                throw StateError('This card is already attached to another supplier.');
              }
              if (linked.isEmpty) {
                await txn.insert('attachments', Attachment(
                  ownerType: 'exhibitor', ownerId: original.id!, kind: 'image',
                  path: entry.value, note: entry.key, createdAt: DateTime.now(),
                ).toMap()..remove('id'));
              }
            }
          }
        }
        if (saveContact) {
          final profile = originalContact == null ? <String, dynamic>{} : object(originalContact.profileJson);
          if (originalContact != null) {
            final contacts = await txn.query('contacts', where: 'id = ? AND exhibitor_id = ?',
              whereArgs: [originalContact.id, original.id]);
            if (contacts.isEmpty || originalContact.toMap().entries.any((entry) => contacts.single[entry.key] != entry.value)) {
              throw StateError('The contact changed elsewhere. Reopen and review before saving.');
            }
          }
          profile['details'] = {...Map<String, dynamic>.from(profile['details'] as Map? ?? {}), ...contactSubset(values)};
          profile['language'] = values['language'] ?? '';
          final contact = Contact(
            exhibitorId: original.id!, name: (values['person'] ?? '').trim().isEmpty ? 'Unnamed company contact' : values['person']!,
            designation: values['role'] ?? '', phone: values['phone'] ?? '', email: values['email'] ?? '',
            whatsapp: values['whatsapp'] ?? '', wechat: values['wechat'] ?? '', profileJson: jsonEncode(profile),
          ).toMap()..remove('id');
          if (originalContact == null) {
            await txn.insert('contacts', contact);
          } else {
            await txn.update('contacts', contact, where: 'id = ?', whereArgs: [originalContact.id]);
          }
        }
        final changes = <String, Object?>{
          for (final key in ['name', 'booth', 'hall', 'country', 'category', 'notes']) key: values[key] ?? '',
          'field_capture_json': jsonEncode(capture),
        };
        await txn.update('exhibitors', changes, where: 'id = ?', whereArgs: [original.id]);
        return Exhibitor.fromMap({...row, ...changes});
      });
      // Failure to remove the resume pointer must not undo a committed supplier.
      if (card != null) {
        try { await card.markSaved(); } on FileSystemException catch (_) { /* Originals remain safe. */ }
      }
      return saved;
    });
  }
}
