import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Rejilla de iconos seleccionables, para categorías y carteras.
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    required this.icons,
    required this.selected,
    required this.color,
    required this.onSelected,
    super.key,
  });

  final List<IconData> icons;
  final int selected;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: icons.map((IconData icon) {
        final bool isSelected = icon.codePoint == selected;
        return InkWell(
          onTap: () => onSelected(icon.codePoint),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              // Seleccionado se pinta con el color elegido de fondo, igual
              // que el distintivo final: así el cambio de color se ve ya en
              // la rejilla y no solo después de guardar.
              color: isSelected ? color : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected
                  ? AppColors.onBadge(color)
                  : scheme.onSurfaceVariant,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Rejilla con los colores de [AppColors.categoryPalette].
class ColorPickerGrid extends StatelessWidget {
  const ColorPickerGrid({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final Color ring = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppColors.categoryPalette.map((int value) {
        final Color swatch = Color(value);
        final bool isSelected = value == selected;
        return Semantics(
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: () => onSelected(value),
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? ring : Colors.transparent,
                  width: 2.4,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.onBadge(swatch),
                      size: 20,
                    )
                  : null,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
