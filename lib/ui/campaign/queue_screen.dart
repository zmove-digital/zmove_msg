import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/batch_scheduler.dart';
import '../../services/notification_service.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.campaign});

  final Campaign campaign;

  /// Nome da rota usado para evitar abrir a mesma fila duas vezes quando o
  /// usuario toca no lembrete com a tela ja aberta.
  static String routeName(int campaignId) => 'queue_$campaignId';

  static Route<void> route(Campaign campaign) => MaterialPageRoute<void>(
    settings: RouteSettings(name: routeName(campaign.id ?? 0)),
    builder: (_) => QueueScreen(campaign: campaign),
  );

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> with WidgetsBindingObserver {
  List<QueueEntry>? _entries;
  bool _waitingReturn = false;
  bool _leftApp = false;
  bool _asking = false;
  bool _autoBusy = false;
  bool _sending = false;
  int? _pendingItemId;

  /// Quando ligado, ao voltar do WhatsApp o app registra o envio e ja abre o
  /// proximo contato, sem pedir confirmacao.
  bool _continuous = true;
  Timer? _advanceTimer;
  Timer? _shortcutTimer;

  /// Envio em lote: intervalo entre contatos (0 = desligado) e janela de
  /// horario em minutos desde 0h.
  late int _intervalMinutes;
  late int _windowStart;
  late int _windowEnd;
  DateTime? _nextReminderAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intervalMinutes = widget.campaign.intervalMinutes;
    _windowStart = widget.campaign.windowStart;
    _windowEnd = widget.campaign.windowEnd;
    unawaited(NotificationService.ensurePermission());
    _load();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _shortcutTimer?.cancel();
    unawaited(NotificationService.hideReturnShortcut());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waitingReturn) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    _waitingReturn = false;
    if (!_leftApp) return;
    _leftApp = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_continuous) {
        _autoConfirmAndAdvance();
      } else {
        _askResult();
      }
    });
  }

  Future<void> _load() async {
    final entries = await context.read<AppState>().entriesFor(
      widget.campaign.id!,
    );
    if (!mounted) return;
    setState(() => _entries = entries);
    _refreshReturnShortcut();
    await _syncBatchSchedule();
  }

  /// (Re)agenda o lembrete do proximo contato. Quando o lote esta ligado, o
  /// proximo contato NAO abre sozinho: o app avisa no intervalo configurado.
  Future<void> _syncBatchSchedule() async {
    final campaignId = widget.campaign.id;
    if (campaignId == null) return;

    final current = _current;
    if (_intervalMinutes <= 0 || current == null) {
      await BatchScheduler.cancel(campaignId);
      if (mounted) setState(() => _nextReminderAt = null);
      return;
    }

    final at = await BatchScheduler.scheduleNext(
      campaignId: campaignId,
      campaignName: widget.campaign.name,
      contactName: current.contact.name,
      remaining: (_entries?.length ?? 0) - _sentCount - _skippedCount,
      intervalMinutes: _intervalMinutes,
      windowStart: _windowStart,
      windowEnd: _windowEnd,
    );
    if (!mounted) return;
    setState(() => _nextReminderAt = at);
  }

  // --------------------------------------------------------------- envio em lote

  /// Opcoes rapidas de intervalo (minutos). 0 = desligado.
  static const _intervalOptions = <int>[0, 5, 10, 20, 30];

  Future<void> _saveBatch({
    int? intervalMinutes,
    int? windowStart,
    int? windowEnd,
  }) async {
    final campaignId = widget.campaign.id;
    if (campaignId == null) return;

    setState(() {
      if (intervalMinutes != null) _intervalMinutes = intervalMinutes;
      if (windowStart != null) _windowStart = windowStart;
      if (windowEnd != null) _windowEnd = windowEnd;
    });

    await context.read<AppState>().updateCampaignBatch(
      campaignId,
      intervalMinutes: _intervalMinutes,
      windowStart: _windowStart,
      windowEnd: _windowEnd,
    );
    await _syncBatchSchedule();
    if (!mounted) return;

    if (_intervalMinutes <= 0) {
      showSnack(context, 'Envio em lote desligado.');
      return;
    }
    final at = _nextReminderAt;
    if (at == null) {
      showSnack(
        context,
        'Envio em lote ativado, mas não foi possível agendar. Verifique as '
        'notificações e os alarmes exatos em Ajustes.',
        error: true,
      );
    } else {
      showSnack(
        context,
        'Envio em lote: lembrete ${BatchScheduler.describe(at)}.',
      );
    }
  }

  Future<void> _pickCustomInterval() async {
    final controller = TextEditingController(
      text: _intervalMinutes > 0 ? '$_intervalMinutes' : '',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Intervalo entre contatos'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutos',
            suffixText: 'min',
            helperText: 'De 1 a 1440 minutos (24 horas)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, minutes);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value < 1 || value > 24 * 60) {
      if (mounted) {
        showSnack(
          context,
          'Use um intervalo entre 1 e 1440 minutos.',
          error: true,
        );
      }
      return;
    }
    await _saveBatch(intervalMinutes: value);
  }

  Future<void> _pickWindow({required bool start}) async {
    final current = start ? _windowStart : _windowEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: start ? 'Início da janela' : 'Fim da janela',
    );
    if (picked == null) return;

    final value = picked.hour * 60 + picked.minute;
    final nextStart = start ? value : _windowStart;
    final nextEnd = start ? _windowEnd : value;
    if (nextStart >= nextEnd) {
      if (mounted) {
        showSnack(
          context,
          'O horário final precisa ser depois do inicial.',
          error: true,
        );
      }
      return;
    }
    await _saveBatch(windowStart: nextStart, windowEnd: nextEnd);
  }

  Widget _buildBatchCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final custom =
        _intervalMinutes > 0 && !_intervalOptions.contains(_intervalMinutes);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_send_rounded,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Envio em lote',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_intervalMinutes > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    BatchScheduler.intervalLabel(_intervalMinutes),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Intervalo entre um contato e o próximo. O app avisa na hora e o '
            'envio continua confirmado por você no WhatsApp.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in _intervalOptions)
                ChoiceChip(
                  label: Text(value == 0 ? 'Desligado' : '$value min'),
                  selected: _intervalMinutes == value,
                  showCheckmark: false,
                  onSelected: (_) => _saveBatch(intervalMinutes: value),
                ),
              ChoiceChip(
                label: Text(
                  custom
                      ? '${BatchScheduler.intervalLabel(_intervalMinutes)}…'
                      : 'Outro…',
                ),
                selected: custom,
                showCheckmark: false,
                onSelected: (_) => _pickCustomInterval(),
              ),
            ],
          ),
          if (_intervalMinutes > 0) ...[
            const Divider(height: 22),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                const Text('Só das'),
                const SizedBox(width: 8),
                _TimeChip(
                  minutes: _windowStart,
                  onTap: () => _pickWindow(start: true),
                ),
                const SizedBox(width: 6),
                const Text('às'),
                const SizedBox(width: 6),
                _TimeChip(
                  minutes: _windowEnd,
                  onTap: () => _pickWindow(start: false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _nextReminderAt == null
                  ? 'Próximo lembrete: será agendado após o envio atual.'
                  : 'Próximo lembrete: '
                        '${BatchScheduler.describe(_nextReminderAt!)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Mantem a notificacao fixa "Volte para o ZMove" atualizada com o contato
  /// da vez. E o atalho de um toque para retornar do WhatsApp.
  void _refreshReturnShortcut() {
    final current = _current;
    if (!_continuous || current == null) {
      unawaited(NotificationService.hideReturnShortcut());
      return;
    }
    final remaining = (_entries?.length ?? 0) - _sentCount - _skippedCount;
    final detail = _intervalMinutes > 0
        ? 'Próximo lembrete em ${BatchScheduler.intervalLabel(_intervalMinutes)}.'
        : 'Faltam $remaining neste envio.';
    unawaited(
      NotificationService.showReturnShortcut(
        title: 'ZMove Msg • ${widget.campaign.name}',
        body: 'Toque aqui para voltar e abrir ${current.contact.name}. $detail',
      ),
    );
  }

  /// Reexibe a notificacao logo depois de abrir o WhatsApp para que ela
  /// apareca como um aviso silencioso sobre a conversa.
  void _armReturnShortcut(QueueEntry entry) {
    _shortcutTimer?.cancel();
    final nextHint = _intervalMinutes > 0
        ? 'o próximo abre em ${BatchScheduler.intervalLabel(_intervalMinutes)}.'
        : 'o próximo contato abre sozinho.';
    unawaited(
      NotificationService.showReturnShortcut(
        title: 'ZMove Msg • ${widget.campaign.name}',
        body:
            'Envie no WhatsApp e toque aqui para voltar. '
            'Agora: ${entry.contact.name}.',
      ),
    );
    _shortcutTimer = Timer(const Duration(milliseconds: 1200), () {
      unawaited(
        NotificationService.showReturnShortcut(
          title: 'ZMove Msg • ${widget.campaign.name}',
          body: 'Envie no WhatsApp e toque aqui para voltar: $nextHint',
          alert: true,
        ),
      );
    });
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
                final appState = context.read<AppState>();
                await BatchScheduler.cancel(widget.campaign.id!);
                await appState.deleteCampaign(widget.campaign.id!);
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
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
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
        state.settings.dailyLimit > 0 &&
        state.sentToday >= state.settings.dailyLimit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (limitReached) ...[
          const StatusBanner(
            icon: Icons.pause_circle_outline_rounded,
            color: AppColors.warning,
            text:
                'Você atingiu o limite diário configurado. Recomendamos continuar '
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
                      style: Theme.of(context).textTheme.titleMedium
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
          style: Theme.of(context).textTheme.titleSmall
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
        if (widget.campaign.hasMedia) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.campaign.media.length == 1
                            ? widget.campaign.media.first.name
                            : '${widget.campaign.media.length} anexos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _sendEntry(current),
                      child: const Text('Compartilhar'),
                    ),
                  ],
                ),
                if (widget.campaign.media.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.campaign.media.map((m) => m.name).join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildBatchCard(context),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: _continuous,
            onChanged: (value) {
              setState(() => _continuous = value);
              if (!value) _cancelAutoAdvance();
              _refreshReturnShortcut();
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            secondary: Icon(
              Icons.bolt_rounded,
              color: _continuous
                  ? AppColors.whatsappDark
                  : Theme.of(context).colorScheme.outline,
            ),
            title: const Text(
              'Modo contínuo',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              _continuous
                  ? (_intervalMinutes > 0
                        ? 'Ao voltar do WhatsApp, registra o envio e agenda o '
                              'próximo no intervalo escolhido.'
                        : 'Ao voltar do WhatsApp, registra o envio e abre o '
                              'próximo contato.')
                  : 'Você confirma cada envio manualmente.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _sending ? null : () => _sendEntry(current),
          icon: Icon(
            widget.campaign.hasMedia
                ? Icons.attach_file_rounded
                : Icons.chat_rounded,
          ),
          label: Text(
            widget.campaign.hasMedia
                ? (widget.campaign.media.length > 1
                      ? 'Abrir WhatsApp com anexos'
                      : 'Abrir WhatsApp com anexo')
                : 'Abrir WhatsApp e enviar',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.whatsappDark,
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (_continuous) ...[
          const SizedBox(height: 8),
          Text(
            _intervalMinutes > 0
                ? 'Envie no WhatsApp e toque na notificação "ZMove Msg" para '
                      'voltar. O próximo lembrete chega em '
                      '${BatchScheduler.intervalLabel(_intervalMinutes)}.'
                : (widget.campaign.hasMedia
                      ? 'Envie no WhatsApp e toque na notificação "ZMove Msg" '
                            'para voltar: o próximo abre sozinho.'
                      : 'Envie no WhatsApp e toque na notificação "ZMove Msg" '
                            'para voltar: o próximo contato abre sozinho.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _sendEntry(QueueEntry entry) async {
    if (_sending) return;
    _sending = true;
    _pendingItemId = entry.item.id;
    _armReturnShortcut(entry);
    try {
      if (widget.campaign.hasMedia) {
        await _shareMedia(entry);
      } else {
        await _openWhatsApp(entry);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _openWhatsApp(QueueEntry entry) async {
    // Marca antes de abrir: a confirmacao acontece no retorno ao app.
    _waitingReturn = true;
    _leftApp = false;
    final opened = await WhatsAppService.openChat(
      phone: entry.contact.phone,
      text: entry.item.renderedText,
    );
    if (!mounted) return;
    if (!opened) {
      _waitingReturn = false;
      _pendingItemId = null;
      showSnack(
        context,
        'Não foi possível abrir o WhatsApp. Verifique se ele está instalado.',
        error: true,
      );
      return;
    }
  }

  Future<void> _shareMedia(QueueEntry entry) async {
    final paths = widget.campaign.media
        .map((media) => media.path)
        .toList(growable: false);
    var found = 0;
    for (final path in paths) {
      if (await File(path).exists()) found++;
    }
    if (found == 0) {
      if (mounted) {
        showSnack(context, 'Os anexos não foram encontrados.', error: true);
      }
      _pendingItemId = null;
      return;
    }
    final shared = await WhatsAppService.shareMedia(
      paths: paths,
      text: entry.item.renderedText,
    );
    if (!mounted) return;
    if (!shared) {
      _pendingItemId = null;
      showSnack(context, 'Compartilhamento cancelado.', error: true);
      return;
    }

    // O compartilhamento pode terminar com o app ainda em segundo plano
    // (usuario no WhatsApp) ou ja de volta ao app.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      if (_continuous) {
        await _autoConfirmAndAdvance();
      } else {
        await _askResult();
      }
    } else {
      _waitingReturn = true;
      _leftApp = true;
    }
  }

  Future<void> _autoConfirmAndAdvance() async {
    if (_autoBusy || !mounted) return;
    final itemId = _pendingItemId;
    if (itemId == null) return;

    QueueEntry? entry;
    for (final item in _entries ?? const <QueueEntry>[]) {
      if (item.item.id == itemId) {
        entry = item;
        break;
      }
    }
    if (entry == null || entry.item.status != SendStatus.pending) return;

    _autoBusy = true;
    try {
      await context.read<AppState>().setItemStatus(entry.item, SendStatus.sent);
      await _load();
    } finally {
      _autoBusy = false;
      _pendingItemId = null;
    }
    if (!mounted) return;

    final next = _current;
    if (next == null) {
      showSnack(
        context,
        'Envio concluído: $_sentCount mensagem(ns) enviada(s).',
      );
      return;
    }

    if (_intervalMinutes > 0) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      final at = _nextReminderAt;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            at == null
                ? '${entry.contact.name}: enviado. O próximo lembrete será agendado.'
                : '${entry.contact.name}: enviado. Próximo lembrete '
                      '${BatchScheduler.describe(at)}.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () => _undoAuto(entry!),
          ),
        ),
      );
      return;
    }

    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || !_continuous) return;
      final current = _current;
      if (current != null) _sendEntry(current);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1800),
        content: Text(
          '${entry.contact.name}: enviado. Abrindo ${next.contact.name}...',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () => _undoAuto(entry!),
        ),
      ),
    );
  }

  Future<void> _undoAuto(QueueEntry entry) async {
    _cancelAutoAdvance(clearSnack: false);
    await context.read<AppState>().setItemStatus(
      entry.item,
      SendStatus.pending,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showSnack(context, 'Registro desfeito. O contato voltou para a fila.');
  }

  void _cancelAutoAdvance({bool clearSnack = true}) {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _pendingItemId = null;
    if (clearSnack && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
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
                style: Theme.of(context).textTheme.titleLarge
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
    _pendingItemId = null;

    if (result != null && mounted) {
      await _mark(entry, result);
    }
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.minutes, required this.onTap});

  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hours = (minutes ~/ 60).toString().padLeft(2, '0');
    final mins = (minutes % 60).toString().padLeft(2, '0');
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text('$hours:$mins'),
    );
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
          child: const Icon(
            Icons.check_rounded,
            size: 48,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Envio concluído',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          campaign.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}
