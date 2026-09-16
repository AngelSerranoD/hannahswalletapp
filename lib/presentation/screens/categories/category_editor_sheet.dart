import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/i18n/cjk_font_loader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/icon_catalog.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/repositories/repositories.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

/// Abre el editor de categorías y devuelve el `id` guardado, o `null` si se
/// cancela.
///
/// Devolver el id es lo que permite a quien lo abre —el formulario de un
/// movimiento o el de un límite— marcar la categoría recién creada sin que el
/// usuario tenga que buscarla entre las demás.
Future<String?> openCategoryEditor(
  BuildContext context, {
  required TransactionType type,
  CategoryEntity? existing,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategoryEditorSheet(type: type, existing: existing),
  );
}

/// Alta y edición de categorías: nombre, icono y color.
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
            Row(
              children: <Widget>[
                // Vista previa: el distintivo tal cual quedará en las listas.
                IconBadge(iconCode: _iconCode, colorValue: _colorValue),
                const SizedBox(width: 14),
                Text(
                  isEditing ? 'Editar categoría' : 'Nueva categoría',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              inputFormatters: const <TextInputFormatter>[CjkFontTrigger()],
              controller: _name,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 20),
            Text('Color', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            ColorPickerGrid(
              selected: _colorValue,
              onSelected: (int value) => setState(() => _colorValue = value),
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
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.danger),
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

    final CategoryEntity? existing = widget.existing;
    final DateTime now = AppClock.now();
    final CategoryRepository repo = ref.read(categoryRepositoryProvider);
    final CategoryEntity category = CategoryEntity(
      id: existing?.id ?? IdGenerator.newId(),
      name: name,
      iconCode: _iconCode,
      colorValue: _colorValue,
      type: existing?.type ?? widget.type,
      isSystem: existing?.isSystem ?? false,
      sortOrder: existing?.sortOrder ?? 9999,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (existing == null) {
        await repo.create(category);
      } else {
        await repo.update(category);
      }
      if (!mounted) return;
      Navigator.of(context).pop(category.id);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }
}
