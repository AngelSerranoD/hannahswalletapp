import 'dart:math' as math;

import '../../core/error/failures.dart';
import '../entities/budget_entity.dart';
import '../entities/category_entity.dart';

/// Reglas de los presupuestos, las mismas para los dos backends.
///
/// Antes vivían dos veces: en SQL con un `NOT EXISTS` para el móvil y
/// reescritas en Dart para la web. Dos copias de una regla acaban
/// discrepando, y aquí discrepar significa que el mismo mes muestra límites
/// distintos según dónde abras la app. Ahora cada backend solo aporta los
/// datos (presupuestos, categorías y gasto por categoría) y la decisión se
/// toma en un único sitio que además se puede probar sin base de datos.
abstract final class BudgetPlanner {
  /// Presupuestos que mandan en el mes [monthKey].
  ///
  /// Primero los puntuales de ese mes. Después las plantillas, salvo las que
  /// un puntual ya sustituye:
  ///
  ///  * la plantilla global, si el mes tiene su propio global;
  ///  * una plantilla de categorías, si comparte ALGUNA categoría con un
  ///    puntual. Basta con una: conservarla contaría dos veces el gasto de la
  ///    categoría compartida.
  static List<BudgetEntity> effectiveFor(
    Iterable<BudgetEntity> budgets,
    String monthKey,
  ) {
    final List<BudgetEntity> live =
        budgets.where((BudgetEntity b) => !b.isDeleted).toList(growable: false);
    final List<BudgetEntity> specific = live
        .where((BudgetEntity b) => b.monthKey == monthKey)
        .toList(growable: false);

    final bool monthHasGlobal = specific.any((BudgetEntity b) => b.isGlobal);
    final Set<String> overridden = <String>{
      for (final BudgetEntity b in specific) ...b.categoryIds,
    };

    return <BudgetEntity>[
      ...specific,
      ...live.where((BudgetEntity b) =>
          b.isRecurringTemplate &&
          (b.isGlobal
              ? !monthHasGlobal
              : !b.categoryIds.any(overridden.contains))),
    ];
  }

  /// Consumo de los presupuestos vigentes en [monthKey].
  ///
  /// [spentByCategory] es el gasto del mes agrupado por categoría, con la
  /// clave `null` para lo que no tiene categoría. El global suma todo; un
  /// límite, solo sus categorías.
  static List<BudgetProgress> progress({
    required Iterable<BudgetEntity> budgets,
    required Map<String, CategoryEntity> categories,
    required Map<String?, int> spentByCategory,
    required String monthKey,
  }) {
    final int totalSpent =
        spentByCategory.values.fold(0, (int sum, int cents) => sum + cents);

    return effectiveFor(budgets, monthKey).map((BudgetEntity b) {
      return BudgetProgress(
        budget: b,
        monthKey: monthKey,
        spentCents: b.isGlobal
            ? totalSpent
            : b.categoryIds.fold(
                0,
                (int sum, String id) => sum + (spentByCategory[id] ?? 0),
              ),
        categories: <CategoryEntity>[
          for (final String id in b.categoryIds)
            if (categories[id] case final CategoryEntity c) c,
        ],
      );
    }).toList()
      ..sort(_displayOrder);
  }

  /// Global primero; después en el orden de sus categorías.
  static int _displayOrder(BudgetProgress a, BudgetProgress b) {
    if (a.budget.isGlobal != b.budget.isGlobal) {
      return a.budget.isGlobal ? -1 : 1;
    }
    final int byOrder = _firstSortOrder(a).compareTo(_firstSortOrder(b));
    return byOrder != 0
        ? byOrder
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  static int _firstSortOrder(BudgetProgress p) => p.categories.isEmpty
      ? 1 << 30
      : p.categories.map((CategoryEntity c) => c.sortOrder).reduce(math.min);

  /// Valida [candidate] frente a los presupuestos [existing] y devuelve lo que
  /// hay que guardar.
  ///
  ///  * El nombre se recorta, y vacío equivale a no tenerlo.
  ///  * Solo puede haber un global por vigencia: guardar otro actualiza el que
  ///    ya había en lugar de duplicarlo.
  ///  * Una categoría no puede estar en dos límites con la misma vigencia: su
  ///    gasto contaría en los dos y el reparto del mes dejaría de cuadrar.
  static BudgetEntity prepareSave(
    BudgetEntity candidate, {
    required Iterable<BudgetEntity> existing,
    required Map<String, CategoryEntity> categories,
  }) {
    if (candidate.limitCents <= 0) {
      throw const ValidationFailure('El límite debe ser mayor que cero.');
    }

    final String name = candidate.name?.trim() ?? '';
    final BudgetEntity clean = candidate.copyWith(
      name: name,
      clearName: name.isEmpty,
      // `toSet` conserva el orden de inserción: es el que eligió el usuario.
      categoryIds: candidate.categoryIds.toSet().toList(growable: false),
    );

    final Iterable<BudgetEntity> sameScope = existing.where((BudgetEntity b) =>
        !b.isDeleted && b.id != clean.id && b.monthKey == clean.monthKey);

    if (clean.isGlobal) {
      final BudgetEntity? current =
          sameScope.where((BudgetEntity b) => b.isGlobal).firstOrNull;
      return current == null
          ? clean
          : current.copyWith(
              limitCents: clean.limitCents,
              name: clean.name,
              clearName: clean.name == null,
            );
    }

    for (final BudgetEntity other in sameScope) {
      final String? shared =
          clean.categoryIds.where(other.categoryIds.contains).firstOrNull;
      if (shared == null) continue;
      throw ValidationFailure(
        '"${categories[shared]?.name ?? 'Una categoría'}" ya está en el límite '
        '"${nameOf(other, categories)}". Quítala de allí antes de añadirla aquí.',
      );
    }
    return clean;
  }

  /// Nombre con el que se reconoce un presupuesto fuera de su tarjeta.
  static String nameOf(
    BudgetEntity budget,
    Map<String, CategoryEntity> categories,
  ) {
    return BudgetProgress(
      budget: budget,
      spentCents: 0,
      monthKey: budget.monthKey ?? '',
      categories: <CategoryEntity>[
        for (final String id in budget.categoryIds)
          if (categories[id] case final CategoryEntity c) c,
      ],
    ).displayName;
  }
}
