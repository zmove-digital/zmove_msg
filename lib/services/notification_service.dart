import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notificacoes locais usadas para lembrar o usuario de continuar um envio
/// agendado. Nao envia mensagens sozinho (isso exigiria a API oficial).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'zmove_lembretes';
  static const _channelName = 'Lembretes de envio';
  static const _channelDescription =
      'Avisos para continuar um envio agendado no ZMove Msg';

  static bool _initialized = false;

  /// Retorna o id da campanha quando o app foi aberto por um toque na
  /// notificacao (app estava fechado).
  static Future<int?> init({required void Function(int campaignId) onOpen}) async {
    if (_initialized) return null;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('ic_notification');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final campaignId = int.tryParse(response.payload ?? '');
        if (campaignId != null) onOpen(campaignId);
      },
    );

    final details = await _plugin.getNotificationAppLaunchDetails();
    _initialized = true;

    if (details?.didNotificationLaunchApp ?? false) {
      return int.tryParse(details?.notificationResponse?.payload ?? '');
    }
    return null;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;

    return await android.requestNotificationsPermission() ?? false;
  }

  /// Abre a tela do sistema para permitir alarmes exatos (Android 12+).
  /// Se negado, os lembretes usam modo aproximado.
  static Future<void> requestExactAlarms() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  static Future<bool> hasPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      styleInformation: BigTextStyleInformation(''),
    ),
  );

  /// Agenda um lembrete. Usa horario exato quando permitido e cai para
  /// "inexact" quando o Android nega a permissao.
  static Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required int campaignId,
  }) async {
    if (!_initialized) return false;

    final when = tz.TZDateTime.from(at.toUtc(), tz.UTC);
    if (when.isBefore(tz.TZDateTime.now(tz.UTC))) return false;

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '$campaignId',
      );
      return true;
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$campaignId',
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id: id);
  }

  static Future<void> showTest() async {
    if (!_initialized) return;
    await _plugin.show(
      id: 1,
      title: 'ZMove Msg',
      body: 'Notificações funcionando. Você será avisado nos envios agendados.',
      notificationDetails: _details,
    );
  }
}
