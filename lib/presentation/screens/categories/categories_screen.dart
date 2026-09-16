import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import 'category_actions.dart';
import 'category_editor_sheet.dart';

/// Categorías de gasto e ingreso, en dos pestañas.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const AppTitle('Categorías'),
          bottom: const TabBar(
            tabs: <Widget>[Tab(text: 'Gastos'), Tab(text: 'Ingresos')],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _CategoryList(type: TransactionType.expense),
            _CategoryList(type: TransactionType.income),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategoryEntity>> categories =
        ref.watch(categoriesProvider(type));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-cat-${type.dbValue}',
        onPressed: () => openCategoryEditor(context, type: type),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: switch (categories) {
        AsyncData<List<CategoryEntity>>(:final List<CategoryEntity> value)
            when value.isEmpty =>
          EmptyState(
            icon: Icons.category_outlined,
            title: 'Sin categorías',
            message: 'Crea la primera para poder clasificar tus movimientos.',
            actionLabel: 'Crear categoría',
            onAction: () => openCategoryEditor(context, type: type),
          ),
        AsyncData<List<CategoryEntity>>(:final List<CategoryEntity> value) =>
          ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
            itemCount: value.length,
            onReorder: (int oldIndex, int newIndex) =>
                _reorder(ref, value, oldIndex, newIndex),
            itemBuilder: (BuildContext context, int index) => _CategoryRow(
              key: ValueKey<String>(value[index].id),
              category: value[index],
              index: index,
            ),
          ),
        AsyncError<List<CategoryEntity>>(:final Object error) =>
          FailureView(message: error.toString()),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _reorder(
    WidgetRef ref,
    List<CategoryEntity> current,
    int oldIndex,
    int newIndex,
  ) {
    // ReorderableListView entrega el índice de destino contando el hueco que
    // deja el elemento arrastrado; hay que corregirlo.
    if (newIndex > oldIndex) newIndex -= 1;
    final List<CategoryEntity> reordered = List<CategoryEntity>.of(current);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    ref.read(categoryRepositoryProvider).reorder(
          reordered.map((CategoryEntity c) => c.id).toList(growable: false),
        );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.category,
    required this.index,
    super.key,
  });

  final CategoryEntity category;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => openCategoryEditor(
          context,
          type: category.type,
          existing: category,
        ),
        child: Row(
          children: <Widget>[
            IconBadge(
              iconCode: category.iconCode,
              colorValue: category.colorValue,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                category.name,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: () => confirmDeleteCategory(context, ref, category),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
