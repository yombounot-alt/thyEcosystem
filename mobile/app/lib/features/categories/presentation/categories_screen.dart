import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/async_view.dart';
import '../application/categories_providers.dart';
import '../data/category_models.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<String?> _askName(BuildContext context, {String? initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(initial == null ? 'Nouvelle catégorie' : 'Renommer la catégorie'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
              textCapitalization: TextCapitalization.sentences,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context);
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(context, () async {
      await ref.read(categoriesApiProvider).create(name);
      ref.invalidate(categoriesProvider);
    });
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Category category) async {
    final name = await _askName(context, initial: category.name);
    if (name == null || name.isEmpty || name == category.name || !context.mounted) return;
    await _run(context, () async {
      await ref.read(categoriesApiProvider).rename(category.id, name);
      ref.invalidate(categoriesProvider);
    });
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Supprimer la catégorie ?'),
            content: Text(
              '« ${category.name} » sera supprimée. Les produits associés restent, sans catégorie.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(categoriesApiProvider).delete(category.id);
      ref.invalidate(categoriesProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Catégories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Catégorie'),
      ),
      body: AsyncView(
        value: categories,
        onRetry: () => ref.invalidate(categoriesProvider),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              message: 'Aucune catégorie.\nCréez-en une pour organiser vos produits.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final category = items[i];
              return ListTile(
                title: Text(category.name),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') _rename(context, ref, category);
                    if (action == 'delete') _delete(context, ref, category);
                  },
                  itemBuilder:
                      (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renommer')),
                        PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                      ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
