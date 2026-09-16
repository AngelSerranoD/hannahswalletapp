import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/repositories/repositories.dart';
import '../../widgets/common.dart';
import 'category_editor_sheet.dart';

/// Menú de una categoría: editarla (nombre, icono y color) o eliminarla.
///
/// Aparece al mantener pulsada una categoría en el editor de un límite, para
/// no tener que salir a Ajustes solo para cambiarle el color.
Future<void> showCategoryActions(
  BuildContext context,
  WidgetRef ref,
  CategoryEntity category,
) async {
  final _CategoryAction? action = await showModalBottomSheet<_CategoryAction>(
    context: context,
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: IconBadge(
              iconCode: category.iconCode,
              colorValue: category.colorValue,
              size: 36,
            ),
            title: Text(category.name),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Editar nombre, icono y color'),
            onTap: () => Navigator.of(sheet).pop(_CategoryAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Eliminar categoría'),
            onTap: () => Navigator.of(sheet).pop(_CategoryAction.delete),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _CategoryAction.edit:
      await openCategoryEditor(
        context,
        type: category.type,
        existing: category,
      );
    case _CategoryAction.delete:
      await confirmDeleteCategory(context, ref, category);
  }
}

enum _CategoryAction { edit, delete }

/// Pide confirmación y hace el borrado lógico, con opción de deshacer.
///
/// Se consulta antes cuántos movimientos la usan para poder decirlo: "la usan
/// 34 movimientos" cambia la decisión respecto a "no la usa ninguno". Ni los
/// movimientos ni los límites que la incluyen se tocan: la categoría solo deja
/// de ofrecerse al anotar.
Future<bool> confirmDeleteCategory(
  BuildContext context,
  WidgetRef ref,
  CategoryEntity category,
) async {
  final CategoryRepository repo = ref.read(categoryRepositoryProvider);
  final int uses = await repo.usageCount(category.id);
  if (!context.mounted) return false;

  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('Eliminar "${category.name}"'),
      content: Text(
        uses == 0
            ? 'No la usa ningún movimiento. Dejará de aparecer al anotar.'
            : 'La usan $uses movimientos. Se conservan tal cual y seguirán '
                'contando en estadísticas y límites, pero la categoría dejará '
                'de ofrecerse al anotar.',
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
  if (ok != true || !context.mounted) return false;

  await repo.softDelete(category.id);
  if (!context.mounted) return true;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Eliminada: ${category.name}'),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: AppColors.warning,
          onPressed: () => repo.restore(category.id),
        ),
      ),
    );
  return true;
}
