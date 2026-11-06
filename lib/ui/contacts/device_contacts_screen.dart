import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/device_contacts_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Lista a agenda do aparelho e permite escolher, um a um, quais contatos
/// importar. Nada e importado automaticamente.
class DeviceContactsScreen extends StatefulWidget {
  const DeviceContactsScreen({super.key});

  @override
  State<DeviceContactsScreen> createState() => _DeviceContactsScreenState();
}

class _DeviceContactsScreenState extends State<DeviceContactsScreen> {
  static const _service = DeviceContactsService();

  final _searchController = TextEditingController();
  final Set<String> _selected = {};
  List<DeviceContactOption> _options = [];
  bool _loading = true;
  bool _importing = false;
  bool _permissionPermanentlyDenied = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionPermanentlyDenied = false;
    });

    try {
      final options = await _service.load(
        defaultDdi: context.read<AppState>().settings.defaultDdi,
      );
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } on ContactsPermissionDeniedException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _permissionPermanentlyDenied = error.permanently;
        _error = error.permanently
            ? 'O acesso à agenda foi negado permanentemente. Abra os ajustes do '
                  'aplicativo e permita o acesso a contatos.'
            : 'O acesso à agenda foi negado. Toque em tentar novamente e permita '
                  'o acesso quando o Android perguntar.';
      });
    } on ContactsUnavailableException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler a agenda deste aparelho.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler a agenda deste aparelho.';
      });
    }
  }

  List<DeviceContactOption> _filtered(List<DeviceContactOption> options) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return options;
    final digits = PhoneUtils.onlyDigits(query);
    return options.where((option) {
      return option.name.toLowerCase().contains(query) ||
          (digits.isNotEmpty && option.phone.contains(digits));
    }).toList();
  }

  void _toggle(String phone) {
    setState(() {
      if (!_selected.remove(phone)) _selected.add(phone);
    });
  }

  void _toggleAll(List<DeviceContactOption> visible, Set<String> existing) {
    final selectable = visible
        .where((option) => !existing.contains(option.phone))
        .map((option) => option.phone)
        .toList();
    final allSelected =
        selectable.isNotEmpty && selectable.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(selectable);
      } else {
        _selected.addAll(selectable);
      }
    });
  }

  Future<void> _import() async {
    final state = context.read<AppState>();
    final selected = _options
        .where((option) => _selected.contains(option.phone))
        .toList();
    if (selected.isEmpty || _importing) return;

    setState(() => _importing = true);
    try {
      final result = await state.importContacts([
        for (final option in selected)
          Contact(name: option.name, phone: option.phone),
      ]);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contatos importados'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultLine(
                icon: Icons.add_circle_outline,
                color: AppColors.success,
                text: '${result.added} contato(s) adicionado(s)',
              ),
              if (result.invalid > 0)
                _ResultLine(
                  icon: Icons.error_outline,
                  color: AppColors.danger,
                  text: '${result.invalid} número(s) ignorado(s)',
                ),
              const SizedBox(height: 6),
              Text(
                'Eles ficaram como "Sem status". Marque a autorização de cada '
                'um antes de incluir em um envio.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Não foi possível importar os contatos.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      await _service.openSystemSettings();
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Abra Ajustes do Android > Apps > ZMove Msg > Permissões.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final existing = {for (final contact in state.contacts) contact.phone};
    final filtered = _filtered(_options);

    return Scaffold(
      appBar: AppBar(title: const Text('Contatos do celular')),
      body: _buildBody(state, existing, filtered),
      bottomNavigationBar: _loading || _error != null || _options.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  _selected.isEmpty
                      ? 'Selecione os contatos'
                      : 'Importar ${_selected.length} contato(s)',
                ),
              ),
            ),
    );
  }

  Widget _buildBody(
    AppState state,
    Set<String> existing,
    List<DeviceContactOption> filtered,
  ) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Lendo a agenda do aparelho...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return EmptyState(
        icon: Icons.contact_phone_outlined,
        title: 'Acesso aos contatos',
        message: _error!,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
            if (_permissionPermanentlyDenied) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir ajustes do app'),
              ),
            ],
          ],
        ),
      );
    }

    if (_options.isEmpty) {
      return EmptyState(
        icon: Icons.contacts_outlined,
        title: 'Nenhum contato com telefone',
        message:
            'A agenda deste aparelho não tem contatos com número válido. '
            'Cadastre manualmente ou importe um CSV.',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Atualizar agenda'),
        ),
      );
    }

    final selectableVisible = filtered
        .where((option) => !existing.contains(option.phone))
        .map((option) => option.phone)
        .toList();
    final allSelected =
        selectableVisible.isNotEmpty &&
        selectableVisible.every(_selected.contains);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Buscar na agenda',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.whatsapp.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.whatsappDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A agenda inclui os contatos sincronizados pelo WhatsApp. '
                    'Quem existe somente dentro do WhatsApp não aparece aqui. '
                    'Contatos já cadastrados ficam bloqueados.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${filtered.length} disponível(is) • '
                  '${_selected.length} selecionado(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (selectableVisible.isNotEmpty)
                TextButton(
                  onPressed: () => _toggleAll(filtered, existing),
                  child: Text(
                    allSelected ? 'Desmarcar todos' : 'Selecionar todos',
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nada encontrado',
                  message: 'Ajuste a busca para encontrar o contato.',
                  action: TextButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: const Text('Limpar busca'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final option = filtered[index];
                    final registered = existing.contains(option.phone);
                    return _DeviceContactTile(
                      option: option,
                      registered: registered,
                      selected: _selected.contains(option.phone),
                      onChanged: () => _toggle(option.phone),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DeviceContactTile extends StatelessWidget {
  const _DeviceContactTile({
    required this.option,
    required this.registered,
    required this.selected,
    required this.onChanged,
  });

  final DeviceContactOption option;
  final bool registered;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: CheckboxListTile(
        value: selected,
        onChanged: registered ? null : (_) => onChanged(),
        controlAffinity: ListTileControlAffinity.leading,
        secondary: ContactAvatar(name: option.name),
        title: Text(
          option.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                PhoneUtils.format(option.phone),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (registered)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Já cadastrado',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
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
