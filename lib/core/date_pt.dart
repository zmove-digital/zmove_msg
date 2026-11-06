const _weekdays = <String>[
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _months = <String>[
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const _monthsShort = <String>[
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

String _two(int value) => value.toString().padLeft(2, '0');

String longDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]}';

String shortDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

String timeOfDay(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

String dateTimeLabel(DateTime date) =>
    '${shortDate(date)} às ${timeOfDay(date)}';

String monthShort(DateTime date) => _monthsShort[date.month - 1];

/// "hoje", "amanhã" ou "dd/mm/aaaa".
String dayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  if (diff == -1) return 'ontem';
  return shortDate(date);
}

String relativeFromNow(DateTime date) {
  final diff = date.difference(DateTime.now());
  if (diff.isNegative) return 'atrasado';
  if (diff.inMinutes < 60) return 'em ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'em ${diff.inHours}h';
  return 'em ${diff.inDays} dias';
}
