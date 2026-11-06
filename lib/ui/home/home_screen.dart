import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../campaign/new_campaign_screen.dart';
import '../campaign/queue_screen.dart';
import '../shell.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pendingCampaigns = state.campaigns
        .where((c) => (state.statsFor(c.id!)?.pending ?? 0) > 0)
        .take(3)
        .toList();
    final authorized =
        state.contacts.where((c) => c.optIn == OptIn.optedIn).length;
    final limit = state.settings.dailyLimit;
    final progress = limit == 0 ? 0.0 : (state.sentToday / limit).clamp(0.0, 1.0);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZMove Msg',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          longDate(DateTime.now()),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Ajustes',
                    onPressed: () => ShellScope.of(context).goToTab(4),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TodayCard(sentToday: state.sentToday, limit: limit, progress: progress),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Contatos',
                      value: '${state.contacts.length}',
                      icon: Icons.people_alt_outlined,
                      hint: '$authorized autorizados',
                      onTap: () => ShellScope.of(context).goToTab(1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTile(
                      label: 'Enviadas (total)',
                      value: '${state.sentTotal}',
                      icon: Icons.mark_email_read_outlined,
                      color: AppColors.whatsappDark,
                      onTap: () => ShellScope.of(context).goToTab(3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (state.contacts.isEmpty) ...[
                SurfaceCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.rocket_launch_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Primeiros passos',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '1. Importe sua lista de clientes (CSV) ou cadastre manualmente.\n'
                        '2. Crie um modelo de mensagem com variáveis como {{primeiro_nome}}.\n'
                        '3. Faça o envio assistido: o app abre o WhatsApp com a mensagem pronta.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.55,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => ShellScope.of(context).goToTab(1),
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Importar contatos'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
              ],
              if (pendingCampaigns.isNotEmpty) ...[
                SectionHeader(
                  title: 'Continuar de onde parou',
                  actionLabel: 'Ver todos',
                  onAction: () => ShellScope.of(context).goToTab(3),
                ),
                for (final campaign in pendingCampaigns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CampaignCard(campaign: campaign),
                  ),
                const SizedBox(height: 12),
              ],
              SectionHeader(title: 'Ações rápidas'),
              FilledButton.icon(
                onPressed: () => _newCampaign(context),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Novo envio'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.whatsappDark,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.upload_file_rounded,
                      label: 'Importar CSV',
                      onTap: () => ShellScope.of(context).goToTab(1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.description_outlined,
                      label: 'Modelos',
                      onTap: () => ShellScope.of(context).goToTab(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.people_outline,
                      label: 'Contatos',
                      onTap: () => ShellScope.of(context).goToTab(1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.event_outlined,
                      label: 'Agendamentos',
                      onTap: () => ShellScope.of(context).goToTab(3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const StatusBanner(
                icon: Icons.shield_outlined,
                text: 'Envio assistido: o ZMove Msg abre o WhatsApp com a mensagem pronta '
                    'e você confirma o envio. Envie apenas para clientes que autorizaram '
                    'o contato e evite disparos em massa.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newCampaign(BuildContext context) async {
    if (context.read<AppState>().contacts.isEmpty) {
      showSnack(context, 'Cadastre ou importe contatos antes de iniciar um envio.');
      ShellScope.of(context).goToTab(1);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewCampaignScreen()),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.sentToday,
    required this.limit,
    required this.progress,
  });

  final int sentToday;
  final int limit;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final reached = limit > 0 && sentToday >= limit;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: reached
              ? const [Color(0xFFB26A00), Color(0xFF8A5200)]
              : const [Color(0xFF0F7B6C), Color(0xFF0A5D52)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Hoje',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (reached)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'limite atingido',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sentToday',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ $limit mensagens',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            reached
                ? 'Você atingiu o limite diário configurado. Ajuste em Ajustes.'
                : 'Restam ${(limit - sentToday).clamp(0, limit)} mensagens no limite diário.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = state.statsFor(campaign.id!);
    final sent = stats?.sent ?? 0;
    final total = stats?.total ?? 0;
    final pending = stats?.pending ?? 0;

    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QueueScreen(campaign: campaign),
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.whatsappDark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$pending pendentes',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.whatsappDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stats?.progress ?? 0,
              minHeight: 6,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$sent de $total enviadas',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}
