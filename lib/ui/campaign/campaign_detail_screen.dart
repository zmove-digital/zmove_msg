import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'queue_screen.dart';

class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = state.statsFor(campaign.id!) ??
        const CampaignStats(total: 0, sent: 0, skipped: 0, pending: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(campaign.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value != 'delete') return;
              final ok = await confirm(
                context,
                title: 'Excluir envio',
                message: 'Excluir "${campaign.name}" e todo o histórico dele?',
                confirmLabel: 'Excluir',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await state.deleteCampaign(campaign.id!);
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Excluir envio')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<QueueEntry>>(
        future: state.entriesFor(campaign.id!),
        builder: (context, snapshot) {
          final entries = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Enviadas',
                      value: '${stats.sent}',
                      icon: Icons.mark_email_read_outlined,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      label: 'Puladas',
                      value: '${stats.skipped}',
                      icon: Icons.skip_next_rounded,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      label: 'Pendentes',
                      value: '${stats.pending}',
                      icon: Icons.schedule_rounded,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: stats.progress,
                  minHeight: 10,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${stats.total} contato(s) no total • criado em '
                '${campaign.createdAt == null ? '—' : dateTimeLabel(campaign.createdAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (campaign.mediaName != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.attach_file_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        campaign.mediaName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (stats.pending > 0)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QueueScreen(campaign: campaign),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Continuar envio (${stats.pending} pendentes)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.whatsappDark,
                  ),
                ),
              const SizedBox(height: 20),
              SectionHeader(title: 'Status por contato'),
              if (entries == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SurfaceCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ContactAvatar(name: entry.contact.name, size: 38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.contact.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  entry.item.sentAt == null
                                      ? _statusLabel(entry.item.status)
                                      : '${_statusLabel(entry.item.status)} • '
                                          '${dateTimeLabel(entry.item.sentAt!)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          _StatusIcon(status: entry.item.status),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: stats.pending > 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QueueScreen(campaign: campaign),
                ),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Continuar'),
            )
          : null,
    );
  }

  static String _statusLabel(SendStatus status) => switch (status) {
        SendStatus.sent => 'Enviado',
        SendStatus.skipped => 'Pulado',
        SendStatus.failed => 'Falhou',
        SendStatus.pending => 'Pendente',
      };
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final SendStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      SendStatus.sent => (Icons.check_circle_rounded, AppColors.success),
      SendStatus.skipped => (Icons.skip_next_rounded, AppColors.warning),
      SendStatus.failed => (Icons.error_rounded, AppColors.danger),
      SendStatus.pending => (Icons.radio_button_unchecked_rounded, AppColors.brand),
    };
    return Icon(icon, color: color, size: 22);
  }
}
