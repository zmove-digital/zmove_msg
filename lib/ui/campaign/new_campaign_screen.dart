import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../core/phone_utils.dart';
import '../../core/template_renderer.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/media_store.dart';
import '../../state/app_state.dart';
import '../templates/template_edit_screen.dart';
import '../widgets/common.dart';
import 'queue_screen.dart';

enum _ContactFilter { authorized, all, unknown }

class NewCampaignScreen extends StatefulWidget {
  const NewCampaignScreen({super.key});

  @override
  State<NewCampaignScreen> createState() => _NewCampaignScreenState();
}

class _NewCampaignScreenState extends State<NewCampaignScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  int _step = 0;
  MessageTemplate? _template;
  String? _mediaPath;
  String? _mediaName;
  final Set<int> _selected = {};
  _ContactFilter _filter = _ContactFilter.authorized;
  String _query = '';
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Envio ${shortDate(DateTime.now())}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _template ??= state.templates.isNotEmpty ? state.templates.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo envio'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step -= 1);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepperHeader(step: _step),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (_step) {
                  0 => _buildMessageStep(state),
                  1 => _buildContactsStep(state),
                  _ => _buildReviewStep(state),
                },
              ),
            ),
            _buildBottomBar(state),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ etapa 1

  Widget _buildMessageStep(AppState state) {
    return ListView(
      key: const ValueKey(0),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nome do envio',
            prefixIcon: Icon(Icons.bookmark_border_rounded),
            helperText: 'Serve para identificar no histórico',
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(
          title: 'Modelo de mensagem',
          actionLabel: 'Novo modelo',
          onAction: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TemplateEditScreen(),
              ),
            );
          },
        ),
        if (state.templates.isEmpty)
          StatusBanner(
            icon: Icons.description_outlined,
            text: 'Nenhum modelo cadastrado. Crie um modelo para continuar.',
            action: TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TemplateEditScreen(),
                  ),
                );
              },
              child: const Text('Criar'),
            ),
          )
        else
          for (final template in state.templates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TemplateOption(
                template: template,
                selected: _template?.id == template.id,
                onTap: () => setState(() => _template = template),
              ),
            ),
        const SizedBox(height: 18),
        SectionHeader(title: 'Anexo (opcional)'),
        if (_mediaPath == null)
          OutlinedButton.icon(
            onPressed: () => _pickMedia(context),
            icon: const Icon(Icons.attach_file_rounded),
            label: const Text('Anexar imagem ou PDF'),
          )
        else
          SurfaceCard(
            child: Row(
              children: [
                Icon(
                  _mediaName?.toLowerCase().endsWith('.pdf') ?? false
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mediaName ?? 'Anexo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Será compartilhado pelo menu do Android',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remover anexo',
                  onPressed: () => setState(() {
                    _mediaPath = null;
                    _mediaName = null;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        const StatusBanner(
          icon: Icons.info_outline,
          text: 'O texto abre direto na conversa do cliente. Para anexos, o '
              'WhatsApp pede que você escolha o contato no compartilhamento '
              '(limitação do próprio WhatsApp para envio assistido).',
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ etapa 2

  List<Contact> _visibleContacts(AppState state) {
    final query = _query.trim().toLowerCase();
    final digits = PhoneUtils.onlyDigits(query);
    return state.contacts.where((contact) {
      final matchesFilter = switch (_filter) {
        _ContactFilter.authorized => contact.optIn == OptIn.optedIn,
        _ContactFilter.unknown => contact.optIn != OptIn.optedOut,
        _ContactFilter.all => true,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return contact.name.toLowerCase().contains(query) ||
          contact.phone.contains(digits) ||
          (contact.group ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildContactsStep(AppState state) {
    final contacts = _visibleContacts(state);
    final authorizedCount =
        state.contacts.where((c) => c.optIn == OptIn.optedIn).length;

    return Column(
      key: const ValueKey(1),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Buscar contato',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              ChoiceChip(
                label: Text('Autorizados ($authorizedCount)'),
                selected: _filter == _ContactFilter.authorized,
                showCheckmark: false,
                onSelected: (_) =>
                    setState(() => _filter = _ContactFilter.authorized),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Não descadastrados'),
                selected: _filter == _ContactFilter.unknown,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = _ContactFilter.unknown),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Todos (${state.contacts.length})'),
                selected: _filter == _ContactFilter.all,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = _ContactFilter.all),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${_selected.length} selecionado(s)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: contacts.isEmpty
                    ? null
                    : () => setState(() {
                          final allSelected =
                              contacts.every((c) => _selected.contains(c.id));
                          if (allSelected) {
                            for (final c in contacts) {
                              _selected.remove(c.id);
                            }
                          } else {
                            _selected.addAll(contacts.map((c) => c.id!));
                          }
                        }),
                child: Text(
                  contacts.isNotEmpty &&
                          contacts.every((c) => _selected.contains(c.id))
                      ? 'Desmarcar'
                      : 'Selecionar todos',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: contacts.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'Nenhum contato neste filtro',
                  message: 'Troque o filtro ou cadastre novos contatos.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    final selected = _selected.contains(contact.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: EdgeInsets.zero,
                        onTap: () => setState(() {
                          if (selected) {
                            _selected.remove(contact.id);
                          } else {
                            _selected.add(contact.id!);
                          }
                        }),
                        child: ListTile(
                          leading: ContactAvatar(name: contact.name, size: 40),
                          title: Text(
                            contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${PhoneUtils.format(contact.phone)}'
                            '${(contact.group ?? '').isEmpty ? '' : ' • ${contact.group}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (contact.optIn == OptIn.optedOut)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.block_outlined,
                                    size: 18,
                                    color: AppColors.danger,
                                  ),
                                ),
                              Checkbox(
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selected.remove(contact.id);
                                  } else {
                                    _selected.add(contact.id!);
                                  }
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ etapa 3

  Widget _buildReviewStep(AppState state) {
    final selectedContacts = state.contacts
        .where((c) => _selected.contains(c.id))
        .toList();
    final optedOut = selectedContacts.where((c) => c.optIn == OptIn.optedOut);
    final previewContact = selectedContacts.isNotEmpty ? selectedContacts.first : null;
    final preview = previewContact == null || _template == null
        ? ''
        : TemplateRenderer.render(
            _template!.body,
            previewContact,
            state.settings,
          );

    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow(
                icon: Icons.bookmark_border_rounded,
                label: 'Envio',
                value: _nameController.text.trim(),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                icon: Icons.description_outlined,
                label: 'Modelo',
                value: _template?.name ?? '—',
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                icon: Icons.people_outline,
                label: 'Contatos',
                value: '${selectedContacts.length} selecionado(s)',
              ),
              if (_mediaName != null) ...[
                const SizedBox(height: 12),
                _SummaryRow(
                  icon: Icons.attach_file_rounded,
                  label: 'Anexo',
                  value: _mediaName!,
                ),
              ],
            ],
          ),
        ),
        if (optedOut.isNotEmpty) ...[
          const SizedBox(height: 12),
          StatusBanner(
            icon: Icons.block_outlined,
            color: AppColors.danger,
            text:
                '${optedOut.length} contato(s) selecionado(s) pediram descadastro. '
                'Recomendamos remover antes de enviar.',
            action: TextButton(
              onPressed: () => setState(() {
                for (final contact in optedOut) {
                  _selected.remove(contact.id);
                }
              }),
              child: const Text('Remover'),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SectionHeader(title: 'Prévia da mensagem'),
        if (preview.isEmpty)
          const StatusBanner(
            icon: Icons.warning_amber_rounded,
            text: 'Selecione um modelo e ao menos um contato.',
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECE5DD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Para: ${previewContact!.name}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5B6B66),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCF8C6),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                    child: Text(
                      preview,
                      style: const TextStyle(
                        color: Color(0xFF14201C),
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const StatusBanner(
          icon: Icons.touch_app_outlined,
          text: 'O envio é assistido: o WhatsApp abre com a mensagem pronta e você '
              'confirma o envio. São cerca de 2 toques por contato.',
        ),
      ],
    );
  }

  Widget _buildBottomBar(AppState state) {
    final canAdvance = switch (_step) {
      0 => _template != null && _nameController.text.trim().isNotEmpty,
      1 => _selected.isNotEmpty,
      _ => _template != null && _selected.isNotEmpty && !_starting,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step -= 1),
                child: const Text('Voltar'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: _step > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: canAdvance
                  ? () {
                      if (_step < 2) {
                        setState(() => _step += 1);
                      } else {
                        _start(state);
                      }
                    }
                  : null,
              icon: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _step < 2 ? Icons.arrow_forward_rounded : Icons.send_rounded,
                    ),
              label: Text(_step < 2 ? 'Continuar' : 'Iniciar envio'),
              style: FilledButton.styleFrom(
                backgroundColor: _step == 2 ? AppColors.whatsappDark : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMedia(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        dialogTitle: 'Escolha o anexo',
      );
      if (file == null || !mounted) return;

      File? persisted;
      if (file.path != null) {
        persisted = await MediaStore.persist(file.path!);
      } else {
        final bytes = await file.readAsBytes();
        final temp = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}${file.name}',
        );
        await temp.writeAsBytes(bytes);
        persisted = await MediaStore.persist(temp.path);
      }

      if (persisted == null || !mounted) return;
      final savedPath = persisted.path;
      final savedName = file.name;
      setState(() {
        _mediaPath = savedPath;
        _mediaName = savedName;
      });
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Não foi possível anexar o arquivo.', error: true);
      }
    }
  }

  Future<void> _start(AppState state) async {
    final template = _template;
    if (template == null) return;
    setState(() => _starting = true);

    final selected = state.contacts
        .where((c) => _selected.contains(c.id))
        .toList(growable: false);

    try {
      final campaignId = await state.createCampaign(
        name: _nameController.text.trim(),
        template: template,
        selected: selected,
        mediaPath: _mediaPath,
        mediaName: _mediaName,
      );
      if (!mounted) return;
      final campaign = state.campaignById(campaignId);
      if (campaign == null) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => QueueScreen(campaign: campaign),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      showSnack(context, 'Não foi possível criar o envio.', error: true);
    }
  }
}

class _StepperHeader extends StatelessWidget {
  const _StepperHeader({required this.step});

  final int step;

  static const _labels = ['Mensagem', 'Contatos', 'Revisar'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i <= step ? colors.primary : colors.outlineVariant,
                ),
              ),
            Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= step
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                  ),
                  child: i < step
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: i <= step ? Colors.white : colors.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: i == step ? FontWeight.w800 : FontWeight.w500,
                    color: i <= step ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final MessageTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.primary : Theme.of(context).dividerColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? colors.primary : colors.outline,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    template.body.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
