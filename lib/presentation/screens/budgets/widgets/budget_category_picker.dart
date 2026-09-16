import 'package:flutter/material.dart';

import '../../../../domain/entities/category_entity.dart';
import '../../../widgets/common.dart';

/// Selección de las categorías de un límite.
///
///  * Tocar una la añade o la quita.
///  * Mantenerla pulsada abre su menú (editar nombre, icono y color, o
///    eliminarla).
///  * Las que ya están en otro límite con la misma vigencia salen
///    deshabilitadas y con el nombre de ese límite: su gasto no puede contar en
///    dos sitios.
///  * Las que el límite tiene pero se eliminaron siguen visibles para poder
///    quitarlas.
class BudgetCategoryPicker extends StatelessWidget {
  const BudgetCategoryPicker({
    required this.available,
    required this.byId,
    required this.selected,
    required this.occupiedBy,
    required this.onToggle,
    required this.onCreate,
    required this.onLongPress,
    super.key,
  });

  /// Categorías de gasto vivas, en su orden.
  final List<CategoryEntity> available;

  /// Todas las categorías, borradas incluidas.
  final Map<String, CategoryEntity> byId;
  final List<String> selected;

  /// Categoría -> nombre del otro límite que ya la usa.
  final Map<String, String> occupiedBy;
  final ValueChanged<String> onToggle;
  final VoidCallback onCreate;
  final ValueChanged<CategoryEntity> onLongPress;

  @override
  Widget build(BuildContext context) {
    final Set<String> live =
        available.map((CategoryEntity c) => c.id).toSet();
    final List<CategoryEntity> retired = <CategoryEntity>[
      for (final String id in selected)
        if (!live.contains(id))
          if (byId[id] case final CategoryEntity c) c,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final CategoryEntity c in available) _chip(c, retired: false),
        for (final CategoryEntity c in retired) _chip(c, retired: true),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Nueva categoría'),
          onPressed: onCreate,
        ),
      ],
    );
  }

  Widget _chip(CategoryEntity c, {required bool retired}) {
    final bool isSelected = selected.contains(c.id);
    final String? owner = occupiedBy[c.id];
    final bool blocked = owner != null && !isSelected;

    return GestureDetector(
      key: ValueKey<String>(c.id),
      onLongPress: retired ? null : () => onLongPress(c),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        onSelected: blocked ? null : (_) => onToggle(c.id),
        avatar: IconBadge(
          iconCode: c.iconCode,
          colorValue: c.colorValue,
          size: 22,
        ),
        label: Text(
          retired
              ? '${c.name} (eliminada)'
              : blocked
                  ? '${c.name} · en $owner'
                  : c.name,
        ),
      ),
    );
  }
}
