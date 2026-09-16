import 'package:equatable/equatable.dart';

import 'category_entity.dart';

/// Límite de gasto.
///
/// Un único modelo cubre los dos tipos de presupuesto de la app:
///
///  * [categoryIds] vacía  -> presupuesto GLOBAL del mes ("no gastar más de
///    1200 EUR en total").
///  * [categoryIds] con valores -> límite para ESAS categorías juntas ("Ocio:
///    200 EUR entre cine, bares y conciertos"). Con una sola categoría es el
///    límite por categoría de siempre.
///
/// [name] es opcional: sin él, la tarjeta se titula con las categorías.
///
/// Y [monthKey] decide su vigencia:
///
///  * `'2026-08'` -> presupuesto puntual, solo para agosto de 2026.
///  * `null`      -> PLANTILLA: se aplica a todos los meses sin uno puntual.
///
/// La plantilla es lo que evita tener que recrear los mismos límites cada día
/// 1. Qué manda en cada mes lo decide `BudgetPlanner.effectiveFor`.
class BudgetEntity extends Equatable {
  const BudgetEntity({
    required this.id,
    required this.limitCents,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.categoryIds = const <String>[],
    this.monthKey,
    this.isDeleted = false,
  });

  final String id;

  /// Nombre elegido por el usuario. `null` si no le ha puesto ninguno.
  final String? name;

  /// Categorías que cubre el límite, sin repetir. Vacía en el global.
  final List<String> categoryIds;
  final String? monthKey;
  final int limitCents;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isGlobal => categoryIds.isEmpty;

  /// `true` si se repite todos los meses en lugar de aplicarse a uno concreto.
  bool get isRecurringTemplate => monthKey == null;

  BudgetEntity copyWith({
    String? name,
    bool clearName = false,
    List<String>? categoryIds,
    String? monthKey,
    bool clearMonth = false,
    int? limitCents,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return BudgetEntity(
      id: id,
      name: clearName ? null : (name ?? this.name),
      categoryIds: categoryIds ?? this.categoryIds,
      monthKey: clearMonth ? null : (monthKey ?? this.monthKey),
      limitCents: limitCents ?? this.limitCents,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        categoryIds,
        monthKey,
        limitCents,
        isDeleted,
        updatedAt,
      ];
}

/// Un presupuesto con lo que se lleva gastado. Es lo que consume la UI y lo
/// que determina el humor de la mascota.
class BudgetProgress extends Equatable {
  const BudgetProgress({
    required this.budget,
    required this.spentCents,
    required this.monthKey,
    this.categories = const <CategoryEntity>[],
  });

  final BudgetEntity budget;
  final int spentCents;
  final String monthKey;

  /// Las categorías del límite ya resueltas, incluidas las borradas: un límite
  /// no pierde una categoría porque se retire de los selectores.
  final List<CategoryEntity> categories;

  int get limitCents => budget.limitCents;

  /// Lo que queda por gastar. Negativo si se pasó.
  int get remainingCents => limitCents - spentCents;

  bool get isOverspent => spentCents > limitCents;

  /// Fracción consumida SIN recortar: puede pasar de 1.0 para poder decir
  /// "llevas un 140 % del presupuesto".
  double get ratio => limitCents <= 0 ? 0 : spentCents / limitCents;

  /// Fracción recortada a `[0, 1]`, para barras de progreso.
  double get clampedRatio => ratio.clamp(0.0, 1.0);

  int get percent => (ratio * 100).round();

  /// Icono de la tarjeta: el de la categoría si solo hay una. Con varias no
  /// hay uno que las represente a todas y la UI pone uno genérico.
  int? get iconCode => categories.length == 1 ? categories.first.iconCode : null;

  int? get colorValue => categories.isEmpty ? null : categories.first.colorValue;

  /// El nombre propio si lo tiene; si no, el de sus categorías.
  String get displayName {
    final String? custom = budget.name;
    if (custom != null && custom.isNotEmpty) return custom;
    if (budget.isGlobal) return 'Presupuesto global';
    if (categories.isEmpty) return 'Límite sin categorías';
    return categoryNames;
  }

  /// Categorías en una línea: "Cine, Bares y Conciertos".
  String get categoryNames {
    final List<String> names =
        categories.map((CategoryEntity c) => c.name).toList(growable: false);
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }

  @override
  List<Object?> get props => <Object?>[
        budget,
        spentCents,
        monthKey,
        categories,
      ];
}
/// Reparto del presupuesto del mes entre los límites.
///
/// El límite GLOBAL ("Todo el mes") es el dinero TOTAL con el que se cuenta, y
/// cada límite de categorías reserva una parte de ese total. Lo que no está
/// reservado, [availableCents], es lo que aún se puede repartir en límites
/// nuevos: por eso baja cada vez que se añade uno.
///
/// No es una restricción, es información: la app deja pasar un reparto que se
/// exceda del total —a veces se quiere avisar antes de cuadrarlo— y se limita
/// a marcarlo con [isOverAllocated].
class BudgetAllocation extends Equatable {
  const BudgetAllocation({
    required this.totalCents,
    required this.assignedCents,
    required this.limitCount,
    required this.hasGlobalBudget,
  });

  /// Calcula el reparto a partir de los presupuestos vigentes de un mes.
  factory BudgetAllocation.from(Iterable<BudgetProgress> progress) {
    int total = 0;
    int assigned = 0;
    int limits = 0;
    bool hasGlobal = false;

    for (final BudgetProgress p in progress) {
      if (p.budget.isGlobal) {
        total += p.limitCents;
        hasGlobal = true;
      } else {
        assigned += p.limitCents;
        limits++;
      }
    }

    return BudgetAllocation(
      totalCents: total,
      assignedCents: assigned,
      limitCount: limits,
      hasGlobalBudget: hasGlobal,
    );
  }

  /// Dinero total del mes: el límite global.
  final int totalCents;

  /// Suma de los límites de categorías ya creados.
  final int assignedCents;

  /// Cuántos límites de categorías hay (sin contar el global).
  final int limitCount;

  /// `false` si todavía no hay límite global, y por tanto no hay total del que
  /// repartir.
  final bool hasGlobalBudget;

  /// Lo que queda por repartir. Negativo si las categorías suman más que el
  /// total.
  int get availableCents => totalCents - assignedCents;

  bool get isOverAllocated => assignedCents > totalCents;

  /// Fracción del total ya repartida. Sin recortar: puede pasar de 1.
  double get ratio => totalCents <= 0 ? 0 : assignedCents / totalCents;

  int get percent => (ratio * 100).round();

  /// Disponible al abrir el editor de [existing].
  ///
  /// Al EDITAR un límite de categorías, el importe que ya tenía vuelve a la
  /// bolsa: si no, editar 100 EUR y dejarlos en 100 EUR parecería gastar el
  /// doble.
  int availableForEditing(BudgetEntity? existing) {
    if (existing == null || existing.isGlobal) return availableCents;
    return availableCents + existing.limitCents;
  }

  @override
  List<Object?> get props => <Object?>[
        totalCents,
        assignedCents,
        limitCount,
        hasGlobalBudget,
      ];
}
