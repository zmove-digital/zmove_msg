import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/template_renderer.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class TemplateEditScreen extends StatefulWidget {
  const TemplateEditScreen({super.key, this.template});

  final MessageTemplate? template;

  @override
  State<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends State<TemplateEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _body;
  bool _saving = false;

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template?.name ?? '');
    _body = TextEditingController(text: widget.template?.body ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unknown = TemplateRenderer.unknownTokensIn(_body.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar modelo' : 'Novo modelo'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir modelo',
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
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nome do modelo',
                hintText: 'Ex.: Aviso de pedido pronto',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Dê um nome para o modelo.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              minLines: 8,
              maxLines: 14,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Mensagem',
                alignLabelWithHint: true,
                hintText:
                    '{{saudacao}}, {{primeiro_nome}}! ...',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Escreva a mensagem.'
                  : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${_body.text.characters.length} caracteres',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                Text(
                  _body.text.characters.length > 1000
                      ? 'Mensagem longa'
                      : 'Mensagem curta',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _body.text.characters.length > 1000
                            ? AppColors.warning
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Variáveis',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Toque para inserir no final do texto.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variable in templateVariables)
                  ActionChip(
                    label: Text(variable.token),
                    tooltip: variable.description,
                    onPressed: () => _insert(variable.token),
                  ),
              ],
            ),
            if (unknown.isNotEmpty) ...[
              const SizedBox(height: 12),
              StatusBanner(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                text:
                    'Variável desconhecida: ${unknown.map((t) => '{{$t}}').join(', ')}. '
                    'Ela será enviada como está.',
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'Prévia',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _PreviewCard(body: _body.text),
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
              label: Text(_isEditing ? 'Salvar alterações' : 'Criar modelo'),
            ),
          ],
        ),
      ),
    );
  }

  void _insert(String token) {
    final text = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final updated = text.replaceRange(start, end, token);
    _body.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    try {
      await state.saveTemplate(
        MessageTemplate(
          id: widget.template?.id,
          name: _name.text.trim(),
          body: _body.text.trim(),
          updatedAt: widget.template?.updatedAt,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Modelo salvo.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Não foi possível salvar o modelo.', error: true);
    }
  }

  Future<void> _delete() async {
    final template = widget.template!;
    final ok = await confirm(
      context,
      title: 'Excluir modelo',
      message: 'Excluir "${template.name}"?',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteTemplate(template.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    const sample = Contact(
      id: 0,
      name: 'Maria Silva',
      phone: '5511912345678',
      group: 'Clientes',
      optIn: OptIn.optedIn,
    );
    final text = TemplateRenderer.render(body, sample, state.settings);
    final preview = text.isEmpty ? 'Sua mensagem aparece aqui.' : text;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECE5DD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Para: Maria Silva • (11) 91234-5678',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }
}
