import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.campaign});

  final Campaign campaign;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> with WidgetsBindingObserver {
  List<QueueEntry>? _entries;
  bool _waitingReturn = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingReturn) {
      _waitingReturn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askResult();
      });
    }
  }

  Future<void> _load() async {
    final entries =
        await context.read<AppState>().entriesFor(widget.campaign.id!);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  QueueEntry? get _current {
    final entries = _entries;
    if (entries == null) return null;
    for (final entry in entries) {
      if (entry.item.status == SendStatus.pending) return entry;
    }
    return null;
  }

  int get _sentCount =>
      _entries?.where((e) => e.item.status == SendStatus.sent).length ?? 0;

  int get _skippedCount =>
      _entries?.where((e) => e.item.status == SendStatus.skipped).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final current = _current;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.campaign.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (entries != null)
              Text(
                '${_sentCount + _skippedCount} de ${entries.length} concluídas',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final ok = await confirm(
                  context,
                  title: 'Excluir envio',
                  message:
                      'Excluir "${widget.campaign.name}"? O progresso será perdido.',
                  confirmLabel: 'Excluir',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                await context
                    .read<AppState>()
                    .deleteCampaign(widget.campaign.id!);
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Excluir envio')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entries == null || entries.isEmpty
                  ? 0
                  : (_sentCount + _skippedCount) / entries.length,
              minHeight: 6,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : current == null
              ? _CompletionView(
                  campaign: widget.campaign,
                  sent: _sentCount,
                  skipped: _skippedCount,
                  total: entries.length,
                  onClose: () => Navigator.pop(context),
                )
              : _buildQueue(context, current, entries.length),
    );
  }

  Widget _buildQueue(BuildContext context, QueueEntry current, int total) {
    final state = context.watch<AppState>();
    final limitReached =
        state.settings.dailyLimit > 0 && state.sentToday >= state.settings.dailyLimit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (limitReached) ...[
          const StatusBanner(
            icon: Icons.pause_circle_outline_rounded,
            color: AppColors.warning,
            text: 'Você atingiu o limite diário configurado. Recomendamos continuar '
                'amanhã para reduzir o risco de bloqueio.',
          ),
          const SizedBox(height: 12),
        ],
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ContactAvatar(name: current.contact.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PhoneUtils.format(current.contact.phone),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              OptInBadge(optIn: current.contact.optIn, compact: true),
            ],
          ),
        ),
        if (current.contact.optIn == OptIn.optedOut) ...[
          const SizedBox(height: 10),
          const StatusBanner(
            icon: Icons.block_outlined,
            color: AppColors.danger,
            text: 'Este contato pediu descadastro. Pule esta mensagem.',
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Mensagem',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFECE5DD),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 340),
              decoration: const BoxDecoration(
                color: Color(0xFFDCF8C6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(3),
                ),
              ),
              child: SelectableText(
                current.item.renderedText,
                style: const TextStyle(
                  color: Color(0xFF14201C),
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
        if (widget.campaign.mediaName != null) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.attach_file_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.campaign.mediaName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => _shareMedia(current),
                  child: const Text('Compartilhar'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _openWhatsApp(current),
          icon: const Icon(Icons.chat_rounded),
          label: const Text('Abrir WhatsApp e enviar'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.whatsappDark,
            minimumSize: const Size.fromHeight(56),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copy(current),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mark(current, SendStatus.sent),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Já enviei'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mark(current, SendStatus.skipped),
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: const Text('Pular'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Faltam ${total - _sentCount - _skippedCount} de $total neste envio.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Future<void> _openWhatsApp(QueueEntry entry) async {
    final opened = await WhatsAppService.openChat(
      phone: entry.contact.phone,
      text: entry.item.renderedText,
    );
    if (!mounted) return;
    if (!opened) {
      showSnack(
        context,
        'Não foi possível abrir o WhatsApp. Verifique se ele está instalado.',
        error: true,
      );
      return;
    }
    _waitingReturn = true;
  }

  Future<void> _shareMedia(QueueEntry entry) async {
    final path = widget.campaign.mediaPath;
    if (path == null || !await File(path).exists()) {
      if (mounted) {
        showSnack(context, 'O anexo não foi encontrado.', error: true);
      }
      return;
    }
    final shared = await WhatsAppService.shareMedia(
      path: path,
      text: entry.item.renderedText,
    );
    if (!mounted) return;
    if (!shared) {
      showSnack(context, 'Compartilhamento cancelado.', error: true);
      return;
    }
    if (mounted) _askResult();
  }

  Future<void> _copy(QueueEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.item.renderedText));
    if (mounted) showSnack(context, 'Mensagem copiada.');
  }

  Future<void> _mark(QueueEntry entry, SendStatus status) async {
    await context.read<AppState>().setItemStatus(entry.item, status);
    await _load();
  }

  Future<void> _askResult() async {
    if (_asking || !mounted) return;
    final entry = _current;
    if (entry == null) return;

    _asking = true;
    final result = await showModalBottomSheet<SendStatus>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mensagem enviada?',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                entry.contact.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, SendStatus.sent),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Sim, enviei'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.whatsappDark,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, SendStatus.skipped),
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Pular este contato'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar e deixar pendente'),
              ),
            ],
          ),
        ),
      ),
    );
    _asking = false;

    if (result != null && mounted) {
      await _mark(entry, result);
    }
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    required this.campaign,
    required this.sent,
    required this.skipped,
    required this.total,
    required this.onClose,
  });

  final Campaign campaign;
  final int sent;
  final int skipped;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Container(
          width: 92,
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 48, color: AppColors.success),
        ),
        const SizedBox(height: 20),
        Text(
          'Envio concluído',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          campaign.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Enviadas',
                value: '$sent',
                icon: Icons.mark_email_read_outlined,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricTile(
                label: 'Puladas',
                value: '$skipped',
                icon: Icons.skip_next_rounded,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onClose,
          icon: const Icon(Icons.home_rounded),
          label: const Text('Voltar ao início'),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Concluído em ${dateTimeLabel(DateTime.now())}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ],
    );
  }
}
