import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_pt.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'template_edit_screen.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final templates = state.templates;

    return Scaffold(
      appBar: AppBar(title: const Text('Modelos de mensagem')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo modelo'),
      ),
      body: templates.isEmpty
          ? EmptyState(
              icon: Icons.description_outlined,
              title: 'Nenhum modelo ainda',
              message: 'Crie modelos com variáveis para agilizar seus envios.',
              action: FilledButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Criar modelo'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: templates.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final template = templates[index];
                return SurfaceCard(
                  onTap: () => _open(context, template),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              template.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20),
                            onSelected: (value) {
                              if (value == 'edit') _open(context, template);
                              if (value == 'delete') {
                                _delete(context, state, template);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Editar')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        template.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            template.updatedAt == null
                                ? ''
                                : 'Atualizado em ${dateTimeLabel(template.updatedAt!)}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _open(BuildContext context, [MessageTemplate? template]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplateEditScreen(template: template),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    AppState state,
    MessageTemplate template,
  ) async {
    final ok = await confirm(
      context,
      title: 'Excluir modelo',
      message:
          'Excluir "${template.name}"? Envios já criados não são alterados.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await state.deleteTemplate(template.id!);
  }
}
