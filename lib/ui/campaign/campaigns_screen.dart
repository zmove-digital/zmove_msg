import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'campaign_detail_screen.dart';
import 'new_campaign_screen.dart';
import 'schedules_tab.dart';

class CampaignsScreen extends StatelessWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Envios'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Envios'),
              Tab(text: 'Agendamentos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CampaignsTab(),
            SchedulesTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final state = context.read<AppState>();
            if (state.contacts.isEmpty) {
              showSnack(
                context,
                'Cadastre ou importe contatos antes de iniciar um envio.',
              );
              return;
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NewCampaignScreen(),
              ),
            );
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Novo envio'),
        ),
      ),
    );
  }
}

class _CampaignsTab extends StatelessWidget {
  const _CampaignsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final campaigns = state.campaigns;

    if (campaigns.isEmpty) {
      return const EmptyState(
        icon: Icons.send_outlined,
        title: 'Nenhum envio ainda',
        message: 'Crie um envio escolhendo um modelo e os contatos. '
            'O WhatsApp será aberto com a mensagem pronta.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: campaigns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final campaign = campaigns[index];
        final stats = state.statsFor(campaign.id!) ??
            const CampaignStats(total: 0, sent: 0, skipped: 0, pending: 0);
        return _CampaignTile(campaign: campaign, stats: stats);
      },
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.campaign, required this.stats});

  final Campaign campaign;
  final CampaignStats stats;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (stats) {
      _ when stats.total == 0 => ('Sem contatos', AppColors.warning),
      _ when stats.pending == 0 => ('Concluído', AppColors.success),
      _ when stats.sent + stats.skipped == 0 => ('Não iniciado', AppColors.brand),
      _ => ('Em andamento', AppColors.whatsappDark),
    };

    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CampaignDetailScreen(campaign: campaign),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  campaign.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stats.progress,
              minHeight: 6,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${stats.sent} enviadas • ${stats.pending} pendentes',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              Text(
                campaign.createdAt == null
                    ? ''
                    : dayLabel(campaign.createdAt!),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
