/// Utilitarios de telefone. O numero e sempre armazenado apenas com digitos,
/// incluindo o DDI (ex.: 5511912345678).
class PhoneUtils {
  PhoneUtils._();

  static String onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// Normaliza para o formato aceito pelo wa.me.
  ///
  /// - remove simbolos
  /// - remove zeros de operadora no inicio (ex.: 011...)
  /// - adiciona o DDI padrao quando o numero parece ser local (10 ou 11 digitos)
  static String normalize(String raw, {String defaultDdi = '55'}) {
    var digits = onlyDigits(raw);
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) digits = digits.substring(2);
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 10 || digits.length == 11) {
      digits = '$defaultDdi$digits';
    }
    return digits;
  }

  static bool isValid(String raw, {String defaultDdi = '55'}) {
    final digits = normalize(raw, defaultDdi: defaultDdi);
    return digits.length >= 12 && digits.length <= 15;
  }

  static String format(String raw) {
    final digits = onlyDigits(raw);
    if (digits.isEmpty) return '';

    var d = digits;
    if (d.startsWith('55') && (d.length == 12 || d.length == 13)) {
      d = d.substring(2);
      if (d.length == 11) {
        return '+55 (${d.substring(0, 2)}) '
            '${d.substring(2, 7)}-${d.substring(7)}';
      }
      return '+55 (${d.substring(0, 2)}) '
          '${d.substring(2, 6)}-${d.substring(6)}';
    }

    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return '+$d';
  }

  /// Link universal do WhatsApp com a mensagem pre-preenchida.
  static String waLink(String phone, String text) {
    final digits = normalize(phone);
    return 'https://wa.me/$digits?text=${Uri.encodeComponent(text)}';
  }

  /// Link alternativo (abre direto no app instalado).
  static String whatsappScheme(String phone, String text) {
    final digits = normalize(phone);
    return 'whatsapp://send?phone=$digits&text=${Uri.encodeComponent(text)}';
  }
}
