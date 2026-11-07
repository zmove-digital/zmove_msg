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

  /// Notificacao fixa exibida durante a fila de envio. Tocar nela volta ao
  /// app, que registra o envio e abre o proximo contato.
  static const _returnChannelId = 'zmove_retorno';
  static const _returnChannelName = 'Retorno rápido';
  static const _returnChannelDescription =
      'Atalho fixo para voltar ao ZMove Msg entre um envio e outro';
  static const int returnNotificationId = 9001;

  static bool _initialized = false;
  static bool _permissionAsked = false;

  /// Retorna o id da campanha quando o app foi aberto por um toque na
  /// notificacao (app estava fechado).
  static Future<int?> init({
    required void Function(int campaignId) onOpen,
  }) async {
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
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;

    return await android.requestNotificationsPermission() ?? false;
  }

  /// Abre a tela do sistema para permitir alarmes exatos (Android 12+).
  /// Se negado, os lembretes usam modo aproximado.
  static Future<void> requestExactAlarms() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestExactAlarmsPermission();
  }

  static Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  /// Pede a permissao de notificacoes uma unica vez por sessao. Sem ela o
  /// atalho de retorno nao aparece.
  static Future<bool> ensurePermission() async {
    if (await hasPermission()) return true;
    if (_permissionAsked) return false;
    _permissionAsked = true;
    return requestPermission();
  }

  static Future<void> showReturnShortcut({
    required String title,
    required String body,
    bool alert = false,
  }) async {
    if (!_initialized) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _returnChannelId,
        _returnChannelName,
        channelDescription: _returnChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: !alert,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        styleInformation: const BigTextStyleInformation(''),
      ),
    );
    try {
      await _plugin.show(
        id: returnNotificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // Sem permissao ou canal bloqueado: o fluxo do app continua funcionando.
    }
  }

  static Future<void> hideReturnShortcut() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: returnNotificationId);
    } catch (_) {
      // Ignora falhas ao remover a notificacao.
    }
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
