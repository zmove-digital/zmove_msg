import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/phone_utils.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class ContactFormScreen extends StatefulWidget {
  const ContactFormScreen({super.key, this.contact});

  final Contact? contact;

  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _group;
  late final TextEditingController _notes;
  late OptIn _optIn;
  bool _saving = false;

  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _name = TextEditingController(text: contact?.name ?? '');
    _phone = TextEditingController(
      text: contact == null ? '' : PhoneUtils.format(contact.phone),
    );
    _group = TextEditingController(text: contact?.group ?? '');
    _notes = TextEditingController(text: contact?.notes ?? '');
    _optIn = contact?.optIn ?? OptIn.optedIn;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _group.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar contato' : 'Novo contato'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir contato',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Maria Silva',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'Informe o nome.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')),
                LengthLimitingTextInputFormatter(22),
              ],
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                hintText: '(11) 91234-5678',
                prefixIcon: Icon(Icons.phone_iphone_rounded),
                helperText: 'Pode digitar com ou sem +55',
              ),
              validator: (value) {
                final ddi = context.read<AppState>().settings.defaultDdi;
                if ((value ?? '').trim().isEmpty) {
                  return 'Informe o telefone.';
                }
                if (!PhoneUtils.isValid(value!, defaultDdi: ddi)) {
                  return 'Telefone inválido. Use DDD + número.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _group,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Grupo / tag (opcional)',
                hintText: 'Ex.: Clientes, Leads, VIP',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
                hintText: 'Anotações internas sobre o contato',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Consentimento',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Autorizado'),
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  selected: _optIn == OptIn.optedIn,
                  onSelected: (_) => setState(() => _optIn = OptIn.optedIn),
                ),
                ChoiceChip(
                  label: const Text('Sem status'),
                  avatar: const Icon(Icons.help_outline, size: 18),
                  selected: _optIn == OptIn.unknown,
                  onSelected: (_) => setState(() => _optIn = OptIn.unknown),
                ),
                ChoiceChip(
                  label: const Text('Descadastrado'),
                  avatar: const Icon(Icons.block_outlined, size: 18),
                  selected: _optIn == OptIn.optedOut,
                  onSelected: (_) => setState(() => _optIn = OptIn.optedOut),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Só envie para quem autorizou o contato. Contatos descadastrados '
              'ficam fora das seleções automáticas.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_isEditing ? 'Salvar alterações' : 'Adicionar contato'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final state = context.read<AppState>();
    final phone = PhoneUtils.normalize(
      _phone.text,
      defaultDdi: state.settings.defaultDdi,
    );

    final contact = Contact(
      id: widget.contact?.id,
      name: _name.text.trim(),
      phone: phone,
      group: _group.text.trim().isEmpty ? null : _group.text.trim(),
      optIn: _optIn,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: widget.contact?.createdAt,
      lastSentAt: widget.contact?.lastSentAt,
    );

    try {
      await state.saveContact(contact);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Contato atualizado.' : 'Contato adicionado.',
          ),
        ),
      );
    } on DuplicatePhoneException {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Já existe um contato com esse telefone.', error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Não foi possível salvar o contato.', error: true);
    }
  }

  Future<void> _delete() async {
    final contact = widget.contact!;
    final ok = await confirm(
      context,
      title: 'Excluir contato',
      message: 'Excluir ${contact.name}? O histórico deste contato será removido.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteContact(contact.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }
}
