import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/csv_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'contact_form_screen.dart';

enum _ContactFilter { all, authorized, unknown, optedOut }

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchController = TextEditingController();
  _ContactFilter _filter = _ContactFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Contact> _filtered(List<Contact> contacts) {
    final query = _query.trim().toLowerCase();
    final digits = PhoneUtils.onlyDigits(query);

    return contacts.where((contact) {
      final matchesFilter = switch (_filter) {
        _ContactFilter.all => true,
        _ContactFilter.authorized => contact.optIn == OptIn.optedIn,
        _ContactFilter.unknown => contact.optIn == OptIn.unknown,
        _ContactFilter.optedOut => contact.optIn == OptIn.optedOut,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;

      final matchesText = contact.name.toLowerCase().contains(query) ||
          (contact.group ?? '').toLowerCase().contains(query);
      final matchesPhone = digits.isNotEmpty && contact.phone.contains(digits);
      return matchesText || matchesPhone;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final contacts = _filtered(state.contacts);
    final total = state.contacts.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatos'),
        actions: [
          IconButton(
            tooltip: 'Importar CSV',
            onPressed: () => _importCsv(context),
            icon: const Icon(Icons.upload_file_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _exportCsv(context);
              if (value == 'import') _importCsv(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Importar CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('Exportar contatos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Novo contato'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, telefone ou grupo',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _FilterChip(
                  label: 'Todos ($total)',
                  selected: _filter == _ContactFilter.all,
                  onTap: () => setState(() => _filter = _ContactFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Autorizados',
                  selected: _filter == _ContactFilter.authorized,
                  onTap: () =>
                      setState(() => _filter = _ContactFilter.authorized),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Sem status',
                  selected: _filter == _ContactFilter.unknown,
                  onTap: () => setState(() => _filter = _ContactFilter.unknown),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Descadastrados',
                  selected: _filter == _ContactFilter.optedOut,
                  onTap: () => setState(() => _filter = _ContactFilter.optedOut),
                ),
              ],
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? EmptyState(
                    icon: state.contacts.isEmpty
                        ? Icons.people_outline
                        : Icons.search_off_rounded,
                    title: state.contacts.isEmpty
                        ? 'Nenhum contato ainda'
                        : 'Nada encontrado',
                    message: state.contacts.isEmpty
                        ? 'Importe sua lista em CSV ou cadastre o primeiro contato manualmente.'
                        : 'Ajuste a busca ou o filtro selecionado.',
                    action: state.contacts.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => _importCsv(context),
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Importar CSV'),
                          )
                        : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: contacts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return _ContactTile(
                        contact: contact,
                        onTap: () => _openForm(context, contact),
                        onAuthorize: () => _setOptIn(
                          context,
                          contact,
                          contact.optIn == OptIn.optedIn
                              ? OptIn.unknown
                              : OptIn.optedIn,
                        ),
                        onOptOut: () => _setOptIn(
                          context,
                          contact,
                          contact.optIn == OptIn.optedOut
                              ? OptIn.unknown
                              : OptIn.optedOut,
                        ),
                        onDelete: () => _delete(context, contact),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, [Contact? contact]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactFormScreen(contact: contact),
      ),
    );
  }

  Future<void> _setOptIn(
    BuildContext context,
    Contact contact,
    OptIn optIn,
  ) async {
    if (optIn == OptIn.optedOut) {
      final ok = await confirm(
        context,
        title: 'Descadastrar contato',
        message:
            '${contact.name} não receberá mais mensagens nas seleções automáticas. '
            'Confirma?',
        confirmLabel: 'Descadastrar',
        destructive: true,
      );
      if (!ok) return;
    }
    if (!context.mounted) return;
    await context.read<AppState>().setOptIn(contact.id!, optIn);
  }

  Future<void> _delete(BuildContext context, Contact contact) async {
    final ok = await confirm(
      context,
      title: 'Excluir contato',
      message:
          'Excluir ${contact.name}? O histórico de envios desse contato também será removido.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<AppState>().deleteContact(contact.id!);
    if (context.mounted) showSnack(context, 'Contato excluído.');
  }

  Future<void> _importCsv(BuildContext context) async {
    final state = context.read<AppState>();
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ImportSheet(
        defaultDdi: state.settings.defaultDdi,
      ),
    );
    if (proceed != true || !context.mounted) return;

    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        dialogTitle: 'Escolha o arquivo CSV',
      );
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Não foi possível abrir o seletor de arquivos.',
            error: true);
      }
      return;
    }
    if (file == null || !context.mounted) return;

    try {
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final contacts = CsvService.parse(
        content,
        defaultDdi: state.settings.defaultDdi,
      );
      final result = await state.importContacts(contacts);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importação concluída'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultLine(
                icon: Icons.add_circle_outline,
                color: AppColors.success,
                text: '${result.added} novo(s) contato(s)',
              ),
              _ResultLine(
                icon: Icons.sync_rounded,
                color: AppColors.warning,
                text: '${result.updated} atualizado(s)',
              ),
              if (result.invalid > 0)
                _ResultLine(
                  icon: Icons.error_outline,
                  color: AppColors.danger,
                  text: '${result.invalid} linha(s) ignorada(s)',
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on CsvImportException catch (error) {
      if (context.mounted) {
        showSnack(context, error.message, error: true);
      }
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Falha ao importar o arquivo.', error: true);
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final contacts = context.read<AppState>().contacts;
    if (contacts.isEmpty) {
      showSnack(context, 'Não há contatos para exportar.');
      return;
    }
    final csv = CsvService.exportContacts(contacts);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(csv),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['contatos_zmove.csv'],
        subject: 'Contatos ZMove Msg',
      ),
    );
    if (context.mounted && result.status == ShareResultStatus.success) {
      showSnack(context, 'Arquivo pronto para compartilhar.');
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onTap,
    required this.onAuthorize,
    required this.onOptOut,
    required this.onDelete,
  });

  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onAuthorize;
  final VoidCallback onOptOut;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: ContactAvatar(name: contact.name),
        title: Text(
          contact.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Text(
                PhoneUtils.format(contact.phone),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if ((contact.group ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '• ${contact.group}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OptInBadge(optIn: contact.optIn, compact: true),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (value) => switch (value) {
                'authorize' => onAuthorize(),
                'optOut' => onOptOut(),
                'delete' => onDelete(),
                _ => null,
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'authorize',
                  child: Text('Alternar autorização'),
                ),
                const PopupMenuItem(
                  value: 'optOut',
                  child: Text('Alternar descadastro'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Excluir contato'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}

class _ImportSheet extends StatelessWidget {
  const _ImportSheet({required this.defaultDdi});

  final String defaultDdi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Importar contatos (CSV)',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'O arquivo deve ter as colunas nome e telefone. Grupo e autorização '
            'são opcionais. O separador pode ser vírgula ou ponto e vírgula.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'nome;telefone;grupo;autorizado\n'
              'Maria Silva;11987654321;Clientes;sim\n'
              'João Souza;+(11) 91234-5678;Leads;não',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Telefones sem DDI recebem +$defaultDdi automaticamente. '
            'Contatos já existentes são atualizados pelo telefone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Escolher arquivo'),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
          ),
        ],
      ),
    );
  }
}
