import '../core/date_pt.dart';
import 'notification_service.dart';

/// Agenda os lembretes do envio em lote: um contato por vez, com intervalo
/// configuravel entre eles. O app nao envia nada sozinho — o lembrete abre a
/// fila e o envio continua sendo confirmado por voce no WhatsApp.
class BatchScheduler {
  BatchScheduler._();

  /// Calcula o proximo horario valido a partir de [from], somando o intervalo
  /// e respeitando a janela de horario.
  ///
  /// [windowStart] e [windowEnd] sao minutos desde 0h. Quando
  /// `windowStart >= windowEnd`, nao ha restricao de horario.
  static DateTime nextSlot({
    required DateTime from,
    required int intervalMinutes,
    required int windowStart,
    required int windowEnd,
  }) {
    var candidate = from.add(Duration(minutes: intervalMinutes));
    if (windowStart >= windowEnd) return candidate;

    // No maximo ~1 ano de ajustes, para nunca entrar em loop infinito.
    for (var guard = 0; guard < 400; guard++) {
      final day = DateTime(candidate.year, candidate.month, candidate.day);
      final start = day.add(Duration(minutes: windowStart));
      final end = day.add(Duration(minutes: windowEnd));

      if (candidate.isBefore(start)) return start;
      if (candidate.isBefore(end)) return candidate;

      candidate = day
          .add(const Duration(days: 1))
          .add(Duration(minutes: windowStart));
    }
    return candidate;
  }

  /// Agenda o lembrete para o proximo contato pendente. Retorna o horario
  /// agendado ou null quando nao foi possivel (ou o lote esta desligado).
  static Future<DateTime?> scheduleNext({
    required int campaignId,
    required String campaignName,
    required String contactName,
    required int remaining,
    required int intervalMinutes,
    required int windowStart,
    required int windowEnd,
    DateTime? from,
  }) async {
    if (intervalMinutes <= 0) {
      await cancel(campaignId);
      return null;
    }

    final at = nextSlot(
      from: from ?? DateTime.now(),
      intervalMinutes: intervalMinutes,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    final ok = await NotificationService.scheduleBatchReminder(
      campaignId: campaignId,
      title: 'ZMove Msg • $campaignName',
      body: remaining > 1
          ? 'Hora de enviar para $contactName. Toque para abrir a conversa. '
                'Restam $remaining neste envio.'
          : 'Hora de enviar para $contactName. Toque para abrir a conversa.',
      at: at,
    );
    return ok ? at : null;
  }

  static Future<void> cancel(int campaignId) =>
      NotificationService.cancelBatchReminder(campaignId);

  static Future<bool> isScheduled(int campaignId) =>
      NotificationService.isBatchReminderScheduled(campaignId);

  /// Texto curto do tipo "hoje às 14:35".
  static String describe(DateTime at) => '${dayLabel(at)} às ${timeOfDay(at)}';

  /// Texto para a interface, ex.: "8 min", "1 h 30 min".
  static String intervalLabel(int minutes) {
    if (minutes <= 0) return 'Desligado';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }
}
