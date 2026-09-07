import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_catalog.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../wallets/wallets_screen.dart';

/// Categorías de gasto e ingreso, en dos pestanas.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onPressed: () => _openEditor(context, type: type),
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
            onAction: () => _openEditor(context, type: type),
          ),
        AsyncData<List<CategoryEntity>>(:final List<CategoryEntity> value) =>
          ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
            itemCount: value.length,
            onReorder: (int oldIndex, int newIndex) {
              // ReorderableListView entrega el índice de destino contando el
              // hueco que deja el elemento arrastrado; hay que corregirlo.
              if (newIndex > oldIndex) newIndex -= 1;
              final List<CategoryEntity> reordered =
                  List<CategoryEntity>.of(value);
              final CategoryEntity moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(categoryRepositoryProvider).reorder(
                    reordered.map((CategoryEntity c) => c.id).toList(),
                  );
            },
            itemBuilder: (BuildContext context, int index) {
              final CategoryEntity c = value[index];
              return Padding(
                key: ValueKey<String>(c.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  onTap: () => _openEditor(context, type: type, existing: c),
                  child: Row(
                    children: <Widget>[
                      IconBadge(iconCode: c.iconCode, colorValue: c.colorValue),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          c.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => _confirmDelete(context, ref, c),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        AsyncError<List<CategoryEntity>>(:final Object error) =>
          FailureView(message: error.toString()),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required TransactionType type,
    CategoryEntity? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(type: type, existing: existing),
    );
  }

  /// Aviso antes del borrado lógico.
  ///
  /// Se consulta cuantos movimientos la usan para poder decirlo: "afecta a 34
  /// movimientos" cambia la decision respecto a "afecta a 0".
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CategoryEntity category,
  ) async {
    final int uses = await ref.read(categoryRepositoryProvider).usageCount(category.id);
    if (!context.mounted) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Eliminar "${category.name}"'),
        content: Text(
          uses == 0
              ? 'No la usa ningún movimiento. Desaparecera de los selectores.'
              : 'La usan $uses movimientos. Se conservan tal cual y seguirán '
                  'contando en las estadísticas, pero la categoría dejará de '
                  'ofrecerse al anotar.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(categoryRepositoryProvider).softDelete(category.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Eliminada: ${category.name}'),
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: AppColors.warning,
            onPressed: () =>
                ref.read(categoryRepositoryProvider).restore(category.id),
          ),
        ),
      );
  }
}

/// Alta y edición de categorías.
///
/// Al guardar devuelve el `id` de la categoría (`Navigator.pop(id)`), o `null`
/// si se cancela.
class CategoryEditorSheet extends ConsumerStatefulWidget {
  const CategoryEditorSheet({required this.type, this.existing, super.key});

  final TransactionType type;
  final CategoryEntity? existing;

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  late final TextEditingController _name;
  late int _iconCode;
  late int _colorValue;
  String? _error;

  @override
  void initState() {
    super.initState();
    final CategoryEntity? e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _iconCode = e?.iconCode ?? IconCatalog.categoryIcons.first.codePoint;
    _colorValue = e?.colorValue ?? AppColors.categoryPalette.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isEditing ? 'Editar categoría' : 'Nueva categoría',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 20),
            Text('Icono', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            IconPickerGrid(
              icons: IconCatalog.categoryIcons,
              selected: _iconCode,
              color: Color(_colorValue),
              onSelected: (int code) => setState(() => _iconCode = code),
            ),
            const SizedBox(height: 20),
            Text('Color', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            ColorPickerGrid(
              selected: _colorValue,
              onSelected: (int value) => setState(() => _colorValue = value),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre a la categoría.');
      return;
    }

    final DateTime now = DateTime.now();
    final repo = ref.read(categoryRepositoryProvider);

    final CategoryEntity category = CategoryEntity(
      id: widget.existing?.id ?? IdGenerator.newId(),
      name: name,
      iconCode: _iconCode,
      colorValue: _colorValue,
      type: widget.existing?.type ?? widget.type,
      isSystem: widget.existing?.isSystem ?? false,
      sortOrder: widget.existing?.sortOrder ?? 9999,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (widget.existing == null) {
        await repo.create(category);
      } else {
        await repo.update(category);
      }
      if (!mounted) return;
      // Devuelve el id: quien abra esta hoja desde el formulario de un
      // movimiento puede seleccionar la categoría recién creada sin que el
      // usuario tenga que buscarla entre las demás.
      Navigator.of(context).pop(category.id);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }
}
