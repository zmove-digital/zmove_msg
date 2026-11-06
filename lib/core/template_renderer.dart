import '../data/models.dart';
import 'phone_utils.dart';

class TemplateVariable {
  const TemplateVariable(this.token, this.description);

  final String token;
  final String description;
}

const templateVariables = <TemplateVariable>[
  TemplateVariable('{{nome}}', 'Nome completo do contato'),
  TemplateVariable('{{primeiro_nome}}', 'Primeiro nome'),
  TemplateVariable('{{saudacao}}', 'Bom dia / Boa tarde / Boa noite'),
  TemplateVariable('{{telefone}}', 'Telefone formatado'),
  TemplateVariable('{{grupo}}', 'Grupo/tag do contato'),
  TemplateVariable('{{data}}', 'Data de hoje (dd/mm/aaaa)'),
  TemplateVariable('{{empresa}}', 'Nome da empresa (Ajustes)'),
  TemplateVariable('{{remetente}}', 'Seu nome (Ajustes)'),
];

class TemplateRenderer {
  TemplateRenderer._();

  static final _token = RegExp(r'\{\{\s*(\w+)\s*\}\}', caseSensitive: false);

  static String greeting(DateTime now) {
    if (now.hour < 12) return 'Bom dia';
    if (now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  static Map<String, String> valuesFor(
    Contact contact,
    AppSettings settings, {
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final name = contact.name.trim();
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return {
      'nome': name,
      'primeiro_nome': firstName,
      'saudacao': greeting(date),
      'telefone': PhoneUtils.format(contact.phone),
      'grupo': contact.group ?? '',
      'data': '$day/$month/${date.year}',
      'empresa': settings.companyName,
      'remetente': settings.senderName,
    };
  }

  static String render(
    String body,
    Contact contact,
    AppSettings settings, {
    DateTime? now,
  }) {
    final values = valuesFor(contact, settings, now: now);
    return body.replaceAllMapped(_token, (match) {
      final key = match.group(1)!.toLowerCase();
      return values[key] ?? match.group(0)!;
    }).trim();
  }

  /// Tokens usados no texto (para avisar sobre variaveis desconhecidas).
  static Set<String> tokensIn(String body) => _token
      .allMatches(body)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();

  static Set<String> unknownTokensIn(String body) {
    final known = templateVariables
        .map((v) => v.token.replaceAll(RegExp(r'[{}]'), '').toLowerCase())
        .toSet();
    return tokensIn(body).difference(known);
  }
}
