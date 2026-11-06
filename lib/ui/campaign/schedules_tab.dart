import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'queue_screen.dart';

class SchedulesTab extends StatelessWidget {
  const SchedulesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final schedules = state.schedules;

    if (schedules.isEmpty) {
      return EmptyState(
        icon: Icons.event_outlined,
        title: 'Nenhum lembrete agendado',
        message: 'Programe um horário para o app avisar quando for hora de '
            'continuar um envio.',
        action: FilledButton.icon(
          onPressed: () => createSchedule(context),
          icon: const Icon(Icons.add_alarm_rounded),
          label: const Text('Agendar lembrete'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        const StatusBanner(
          icon: Icons.notifications_active_outlined,
          text: 'O lembrete abre a fila de envio no horário marcado. O envio em si '
              'continua sendo confirmado por você no WhatsApp.',
        ),
        const SizedBox(height: 14),
        for (final schedule in schedules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ScheduleCard(schedule: schedule),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => createSchedule(context),
          icon: const Icon(Icons.add_alarm_rounded),
          label: const Text('Agendar outro lembrete'),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule});

  final ScheduleItem schedule;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final campaign = state.campaignById(schedule.campaignId);
    final pending = state.statsFor(schedule.campaignId)?.pending ?? 0;
    final late = schedule.at.isBefore(DateTime.now());
    final color = late ? AppColors.warning : AppColors.brand;

    return SurfaceCard(
      onTap: campaign == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QueueScreen(campaign: campaign),
                ),
              ),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  schedule.at.day.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  monthShort(schedule.at),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${dayLabel(schedule.at)} às ${timeOfDay(schedule.at)}'
                  '${late ? ' • horário passado' : ' • ${relativeFromNow(schedule.at)}'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (campaign != null)
                  Text(
                    '$pending mensagem(ns) pendente(s)',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancelar lembrete',
            onPressed: () => _delete(context),
            icon: const Icon(Icons.notifications_off_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Cancelar lembrete',
      message: 'Remover o lembrete de ${dateTimeLabel(schedule.at)}?',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final state = context.read<AppState>();
    await NotificationService.cancel(schedule.id!);
    await state.deleteSchedule(schedule.id!);
    if (context.mounted) showSnack(context, 'Lembrete cancelado.');
  }
}

Future<void> createSchedule(BuildContext context) async {
  final state = context.read<AppState>();
  final candidates = state.campaigns
      .where((c) => (state.statsFor(c.id!)?.pending ?? 0) > 0)
      .toList();

  if (candidates.isEmpty) {
    showSnack(
      context,
      'Não há envios com mensagens pendentes para agendar.',
      error: true,
    );
    return;
  }

  final campaign = await showModalBottomSheet<Campaign>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Escolha o envio',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final campaign in candidates)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.send_outlined),
                title: Text(
                  campaign.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${state.statsFor(campaign.id!)?.pending ?? 0} pendente(s)',
                ),
                onTap: () => Navigator.pop(context, campaign),
              ),
          ],
        ),
      ),
    ),
  );
  if (campaign == null || !context.mounted) return;

  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 1, now.month, now.day),
    helpText: 'Dia do lembrete',
    cancelText: 'Cancelar',
    confirmText: 'Escolher',
  );
  if (date == null || !context.mounted) return;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    helpText: 'Horário do lembrete',
    cancelText: 'Cancelar',
    confirmText: 'Escolher',
  );
  if (time == null || !context.mounted) return;

  final at = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!at.isAfter(DateTime.now())) {
    showSnack(context, 'Escolha um horário no futuro.', error: true);
    return;
  }

  final allowed = await NotificationService.requestPermission();
  if (!context.mounted) return;

  final pending = state.statsFor(campaign.id!)?.pending ?? 0;
  final id = await state.addSchedule(
    title: 'Continuar "${campaign.name}"',
    campaignId: campaign.id!,
    at: at,
  );

  final scheduled = await NotificationService.scheduleReminder(
    id: id,
    title: 'Hora de continuar o envio',
    body: '$pending mensagem(ns) pendente(s) em "${campaign.name}"',
    at: at,
    campaignId: campaign.id!,
  );

  if (!context.mounted) return;
  if (!allowed) {
    showSnack(
      context,
      'Lembrete salvo, mas as notificações estão desativadas. '
      'Ative nas permissões do Android ou em Ajustes.',
      error: true,
    );
  } else if (!scheduled) {
    showSnack(
      context,
      'Lembrete salvo, mas não foi possível programar a notificação.',
      error: true,
    );
  } else {
    showSnack(context, 'Lembrete agendado para ${dateTimeLabel(at)}.');
  }
}
