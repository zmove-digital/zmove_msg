import 'package:flutter_test/flutter_test.dart';
import 'package:zmove_msg/core/phone_utils.dart';
import 'package:zmove_msg/core/template_renderer.dart';
import 'package:zmove_msg/data/models.dart';

void main() {
  group('PhoneUtils', () {
    test('normaliza numero local com DDI padrao', () {
      expect(PhoneUtils.normalize('(11) 91234-5678'), '5511912345678');
      expect(PhoneUtils.normalize('011 91234-5678'), '5511912345678');
    });

    test('mantem numero que ja tem DDI', () {
      expect(PhoneUtils.normalize('+55 11 91234-5678'), '5511912345678');
    });

    test('valida numeros', () {
      expect(PhoneUtils.isValid('11912345678'), isTrue);
      expect(PhoneUtils.isValid('123'), isFalse);
    });

    test('gera link do WhatsApp com texto codificado', () {
      final link = PhoneUtils.waLink('11912345678', 'Oi, tudo bem?');
      expect(link, startsWith('https://wa.me/5511912345678?text='));
      expect(link, contains('Oi%2C%20tudo%20bem%3F'));
    });
  });

  group('TemplateRenderer', () {
    const contact = Contact(
      id: 1,
      name: 'Maria Silva',
      phone: '5511912345678',
      group: 'Clientes',
    );

    test('substitui variaveis conhecidas', () {
      final text = TemplateRenderer.render(
        '{{saudacao}}, {{primeiro_nome}}! Grupo: {{grupo}}.',
        contact,
        const AppSettings(senderName: 'João', companyName: 'ZMOVE'),
        now: DateTime(2026, 11, 6, 9),
      );
      expect(text, 'Bom dia, Maria! Grupo: Clientes.');
    });

    test('mantem variaveis desconhecidas', () {
      final text = TemplateRenderer.render(
        'Oi {{nome}}, {{desconhecida}}',
        contact,
        const AppSettings(),
      );
      expect(text, 'Oi Maria Silva, {{desconhecida}}');
    });

    test('detecta variaveis desconhecidas', () {
      expect(
        TemplateRenderer.unknownTokensIn('{{nome}} {{xyz}}'),
        {'xyz'},
      );
    });
  });
}
