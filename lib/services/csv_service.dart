import 'package:csv/csv.dart';

import '../core/phone_utils.dart';
import '../data/models.dart';

class CsvImportException implements Exception {
  const CsvImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CsvService {
  CsvService._();

  static const _nameKeys = ['nome', 'name', 'cliente', 'contato', 'contatos'];
  static const _phoneKeys = [
    'telefone',
    'phone',
    'celular',
    'whatsapp',
    'fone',
    'numero',
    'número',
    'tel',
    'telefone_celular',
  ];
  static const _groupKeys = ['grupo', 'tag', 'categoria', 'group', 'lista'];
  static const _optInKeys = [
    'opt_in',
    'optin',
    'autorizado',
    'consentimento',
    'status',
    'aceite',
  ];

  /// Le um CSV/TXT com colunas: nome, telefone, grupo (opcional),
  /// autorizado (opcional). Aceita separador `,` ou `;` e cabecalho opcional.
  static List<Contact> parse(String raw, {required String defaultDdi}) {
    var content = raw;
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (content.isEmpty) {
      throw const CsvImportException('O arquivo está vazio.');
    }

    final firstLine = content.split('\n').first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    final delimiter = semicolons > commas ? ';' : ',';

    List<List<dynamic>> rows;
    try {
      rows = Csv(
        fieldDelimiter: delimiter,
        autoDetect: false,
        dynamicTyping: false,
      ).decode(content);
    } catch (_) {
      throw const CsvImportException(
        'Não foi possível ler o arquivo. Salve como CSV e tente novamente.',
      );
    }

    rows = rows.where((row) => row.any((c) => c.toString().trim().isNotEmpty)).toList();
    if (rows.isEmpty) {
      throw const CsvImportException('Nenhuma linha encontrada no arquivo.');
    }

    int indexOf(List<String> keys) {
      for (var i = 0; i < rows.first.length; i++) {
        final cell = _normalizeHeader(rows.first[i].toString());
        if (keys.contains(cell)) return i;
      }
      return -1;
    }

    final nameIdx = indexOf(_nameKeys);
    final phoneIdx = indexOf(_phoneKeys);
    final hasHeader = nameIdx >= 0 && phoneIdx >= 0;

    final groupIdx = hasHeader ? indexOf(_groupKeys) : (rows.first.length > 2 ? 2 : -1);
    final optInIdx = hasHeader ? indexOf(_optInKeys) : (rows.first.length > 3 ? 3 : -1);

    final dataRows = hasHeader ? rows.skip(1) : rows;
    final parsed = <Contact>[];

    for (final row in dataRows) {
      String cell(int index) {
        if (index < 0 || index >= row.length) return '';
        return row[index].toString().trim();
      }

      final name = cell(hasHeader ? nameIdx : 0);
      final phoneRaw = cell(hasHeader ? phoneIdx : 1);
      if (name.isEmpty || PhoneUtils.onlyDigits(phoneRaw).isEmpty) continue;

      final phone = PhoneUtils.normalize(phoneRaw, defaultDdi: defaultDdi);
      if (phone.length < 12) continue;

      parsed.add(
        Contact(
          name: name,
          phone: phone,
          group: cell(groupIdx).isEmpty ? null : cell(groupIdx),
          optIn: _parseOptIn(cell(optInIdx)),
          createdAt: DateTime.now(),
        ),
      );
    }

    if (parsed.isEmpty) {
      throw const CsvImportException(
        'Nenhum contato válido encontrado. Verifique as colunas nome e telefone.',
      );
    }
    return parsed;
  }

  static String exportContacts(List<Contact> contacts) {
    final rows = <List<dynamic>>[
      ['nome', 'telefone', 'grupo', 'autorizado', 'notas'],
      for (final c in contacts)
        [
          c.name,
          c.phone,
          c.group ?? '',
          switch (c.optIn) {
            OptIn.optedIn => 'sim',
            OptIn.optedOut => 'não',
            OptIn.unknown => '',
          },
          c.notes ?? '',
        ],
    ];
    return Csv(fieldDelimiter: ';', addBom: true).encode(rows);
  }

  static String _normalizeHeader(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll('ç', 'c')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(' ', '_');

  static OptIn _parseOptIn(String value) {
    final v = _normalizeHeader(value);
    if (v.isEmpty) return OptIn.unknown;
    if (['sim', 's', '1', 'true', 'autorizado', 'opted_in', 'aceito', 'ativo']
        .contains(v)) {
      return OptIn.optedIn;
    }
    if (['nao', 'n', '0', 'false', 'descadastrado', 'opted_out', 'recusou']
        .contains(v)) {
      return OptIn.optedOut;
    }
    return OptIn.unknown;
  }
}
