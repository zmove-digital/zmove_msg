import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/phone_utils.dart';

/// Uma linha selecionavel da agenda do aparelho.
///
/// O mesmo contato pode aparecer mais de uma vez quando possui varios
/// telefones; assim o usuario importa exatamente o numero que usa no WhatsApp.
class DeviceContactOption {
  const DeviceContactOption({required this.name, required this.phone});

  final String name;

  /// Normalizado (somente digitos, com DDI).
  final String phone;
}

class ContactsPermissionDeniedException implements Exception {
  const ContactsPermissionDeniedException({this.permanently = false});

  final bool permanently;
}

class ContactsUnavailableException implements Exception {
  const ContactsUnavailableException(this.message);

  final String message;
}

/// Le a agenda do aparelho (inclui os contatos sincronizados pelo WhatsApp).
class DeviceContactsService {
  const DeviceContactsService();

  Future<List<DeviceContactOption>> load({String defaultDdi = '55'}) async {
    PermissionStatus status;
    try {
      status = await FlutterContacts.permissions.request(PermissionType.read);
    } catch (error) {
      throw ContactsUnavailableException('$error');
    }

    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      throw ContactsPermissionDeniedException(
        permanently:
            status == PermissionStatus.permanentlyDenied ||
            status == PermissionStatus.restricted,
      );
    }

    final List<Contact> deviceContacts;
    try {
      deviceContacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
    } catch (error) {
      throw ContactsUnavailableException('$error');
    }

    final seen = <String>{};
    final options = <DeviceContactOption>[];

    for (final contact in deviceContacts) {
      final name = (contact.displayName ?? '').trim();
      if (name.isEmpty) continue;

      for (final phone in contact.phones) {
        final raw = (phone.normalizedNumber ?? phone.number).trim();
        final normalized = PhoneUtils.normalize(raw, defaultDdi: defaultDdi);
        if (normalized.length < 12 || normalized.length > 15) continue;
        if (!seen.add(normalized)) continue;
        options.add(DeviceContactOption(name: name, phone: normalized));
      }
    }

    options.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.phone.compareTo(b.phone);
    });
    return options;
  }

  Future<void> openSystemSettings() =>
      FlutterContacts.permissions.openSettings();
}
