import 'package:flutter_contacts/flutter_contacts.dart' as device_contacts;

import '../models/models.dart';

class DeviceContactsService {
  const DeviceContactsService._();

  static Future<bool> openCreateContact({
    required Contact contact,
    required Exhibitor supplier,
  }) async {
    final phones = <device_contacts.Phone>[];
    if (contact.phone.trim().isNotEmpty) {
      phones.add(device_contacts.Phone(number: contact.phone.trim()));
    }
    if (contact.whatsapp.trim().isNotEmpty &&
        _normalized(contact.whatsapp) != _normalized(contact.phone)) {
      phones.add(
        device_contacts.Phone(
          number: contact.whatsapp.trim(),
          label: const device_contacts.Label(
            device_contacts.PhoneLabel.custom,
            'WhatsApp',
          ),
        ),
      );
    }

    final deviceContact = device_contacts.Contact(
      name: device_contacts.Name(
        first: contact.name.trim().isEmpty
            ? supplier.name.trim()
            : contact.name.trim(),
      ),
      phones: phones,
      emails: contact.email.trim().isEmpty
          ? const []
          : [
              device_contacts.Email(
                address: contact.email.trim(),
                label: const device_contacts.Label(
                  device_contacts.EmailLabel.work,
                ),
              ),
            ],
      organizations: [
        device_contacts.Organization(
          name: supplier.name.trim(),
          jobTitle: contact.designation.trim().isEmpty
              ? null
              : contact.designation.trim(),
        ),
      ],
    );

    final createdId = await device_contacts.FlutterContacts.native
        .showCreator(contact: deviceContact);
    return createdId != null;
  }

  static String _normalized(String value) =>
      value.replaceAll(RegExp(r'[^0-9+]'), '');
}
