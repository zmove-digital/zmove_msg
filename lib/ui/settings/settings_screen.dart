import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../services/csv_service.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _sender;
  late final TextEditingController _company;
  late final TextEditingController _ddi;
  late final TextEditingController _limit;
  bool? _notificationsEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppState>().settings;
    _sender = TextEditingController(text: settings.senderName);
    _company = TextEditingController(text: settings.companyName);
    _ddi = TextEditingController(text: settings.defaultDdi);
    _limit = TextEditingController(text: settings.dailyLimit.toString());
    _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus() async {
    final enabled = await NotificationService.hasPermission();
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  @override
  void dispose() {
    _sender.dispose();
    _company.dispose();
    _ddi.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionHeader(title: 'Seu negócio'),
          SurfaceCard(
            child: Column(
              children: [
                TextField(
                  controller: _sender,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Seu nome (usado em {{remetente}})',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Empresa (usada em {{empresa}})',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Envio'),
          SurfaceCard(
            child: Column(
              children: [
                TextField(
                  controller: _ddi,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'DDI padrão',
                    hintText: '55',
                    prefixIcon: Icon(Icons.public_rounded),
                    helperText: 'Código do país usado quando o telefone não tem DDI',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Limite diário de mensagens',
                    prefixIcon: Icon(Icons.speed_rounded),
                    helperText: 'Recomendado: até 50 por dia para um número novo',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Salvando...' : 'Salvar ajustes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Notificações'),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _notificationsEnabled == true
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      color: _notificationsEnabled == true
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _notificationsEnabled == true
                            ? 'Notificações ativas'
                            : 'Notificações desativadas',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final granted =
                              await NotificationService.requestPermission();
                          await _refreshNotificationStatus();
                          if (!context.mounted) return;
                          if (!granted) {
                            showSnack(
                              context,
                              'Permissão não concedida. Ative nas configurações do Android.',
                              error: true,
                            );
                          }
                        },
                        child: const Text('Permitir'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await NotificationService.showTest();
                          if (!context.mounted) return;
                          showSnack(context, 'Notificação de teste enviada.');
                        },
                        child: const Text('Testar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () async {
                    await NotificationService.requestExactAlarms();
                  },
                  child: const Text('Permitir alarmes exatos (pontualidade)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Dados'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('Exportar contatos (CSV)'),
                  subtitle: const Text('Compartilhar a lista com backup'),
                  onTap: () => _exportContacts(state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Como funciona o envio'),
                  onTap: () => _showHowItWorks(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Uso responsável'),
                  onTap: () => _showResponsibleUse(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  'ZMove Msg 1.0.0',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Envio assistido via WhatsApp • dados apenas no aparelho',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final ddi = _ddi.text.trim();
    final limit = int.tryParse(_limit.text.trim());

    if (ddi.isEmpty) {
      showSnack(context, 'Informe um DDI válido (ex.: 55).', error: true);
      return;
    }
    if (limit == null || limit < 1 || limit > 2000) {
      showSnack(context, 'Limite diário deve ser entre 1 e 2000.', error: true);
      return;
    }

    setState(() => _saving = true);
    await context.read<AppState>().saveSettings(
          context.read<AppState>().settings.copyWith(
                senderName: _sender.text.trim(),
                companyName: _company.text.trim(),
                defaultDdi: ddi,
                dailyLimit: limit,
              ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(context, 'Ajustes salvos.');
  }

  Future<void> _exportContacts(AppState state) async {
    if (state.contacts.isEmpty) {
      showSnack(context, 'Não há contatos para exportar.');
      return;
    }
    final csv = CsvService.exportContacts(state.contacts);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(utf8.encode(csv), mimeType: 'text/csv'),
        ],
        fileNameOverrides: ['contatos_zmove.csv'],
        subject: 'Contatos ZMove Msg',
      ),
    );
  }

  void _showHowItWorks(BuildContext context) {
    _showInfoDialog(
      context,
      title: 'Como funciona o envio',
      lines: const [
        'O ZMove Msg não envia mensagens sozinho. Ele organiza a fila e abre o '
            'WhatsApp com o texto já preenchido para o contato certo.',
        'Você toca em enviar no WhatsApp e volta ao app. O app pergunta se a '
            'mensagem foi enviada e atualiza o relatório.',
        'Isso mantém o uso dentro dos termos do WhatsApp, sem automação não '
            'oficial e sem risco de banimento por disparo em massa.',
        'Anexos (imagem/PDF) são enviados pelo compartilhamento do Android: o '
            'próprio WhatsApp pede que você escolha o contato.',
        'Lembretes agendados mostram uma notificação no horário marcado e abrem '
            'a fila de envio.',
      ],
    );
  }

  void _showResponsibleUse(BuildContext context) {
    _showInfoDialog(
      context,
      title: 'Uso responsável',
      lines: const [
        'Envie apenas para clientes que autorizaram receber mensagens.',
        'Marque como "descadastrado" quem pedir para sair. O app exclui essas '
            'pessoas das seleções automáticas.',
        'Evite muitos envios no mesmo minuto e respeite o limite diário. '
            'Números novos são mais sensíveis a bloqueios.',
        'Não use listas compradas e não envie conteúdo enganoso ou spam.',
        'O WhatsApp pode bloquear números que recebem muitas denúncias. '
            'O ZMove Msg reduz esse risco, mas não elimina a responsabilidade '
            'de quem envia.',
      ],
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child: Icon(Icons.circle, size: 6),
                      ),
                      Expanded(
                        child: Text(line, style: const TextStyle(height: 1.45)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}
