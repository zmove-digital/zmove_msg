import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/phone_utils.dart';

class WhatsAppService {
  WhatsAppService._();

  /// Abre a conversa do contato com o texto pre-preenchido.
  /// Retorna false quando nao foi possivel abrir o WhatsApp.
  static Future<bool> openChat({
    required String phone,
    required String text,
  }) async {
    final candidates = <Uri>[
      Uri.parse(PhoneUtils.waLink(phone, text)),
      Uri.parse(PhoneUtils.whatsappScheme(phone, text)),
    ];

    for (final uri in candidates) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return true;
      } catch (_) {
        // tenta o proximo formato de link
      }
    }
    return false;
  }

  /// Compartilha midia (imagens/PDF) + legenda. O usuario escolhe o contato
  /// dentro do WhatsApp, pois nao existe link oficial com anexo + destinatario.
  static Future<bool> shareMedia({
    required List<String> paths,
    required String text,
  }) async {
    final files = <XFile>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) files.add(XFile(path));
    }
    if (files.isEmpty) return false;

    final result = await SharePlus.instance.share(
      ShareParams(files: files, text: text, subject: 'ZMove Msg'),
    );
    return result.status == ShareResultStatus.success;
  }
}
