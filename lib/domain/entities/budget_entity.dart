import 'package:equatable/equatable.dart';

/// Límite de gasto.
///
/// Un único modelo cubre los dos tipos de presupuesto de la app:
///
///  * [categoryId] `null`  -> presupuesto GLOBAL del mes ("no gastar mas de
///    1200 EUR en total").
///  * [categoryId] con valor -> límite POR CATEGORIA ("máximo 200 EUR en
///    restaurantes").
///
/// Y [monthKey] decide su vigencia:
///
///  * `'2026-08'` -> presupuesto puntual, solo para agosto de 2026.
///  * `null`      -> PLANTILLA: se aplica a todos los meses sin uno puntual.
///
/// La plantilla es lo que evita tener que recrear los mismos límites cada día
/// 1. Al consultar un mes se busca primero el puntual y, si no hay, se hereda
/// la plantilla (ver `BudgetDao.progressForMonth`).
class BudgetEntity extends Equatable {
  const BudgetEntity({
    required this.id,
    required this.limitCents,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.monthKey,
    this.isDeleted = false,
  });

  final String id;
  final String? categoryId;
  final String? monthKey;
  final int limitCents;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isGlobal => categoryId == null;

  /// `true` si se repite todos los meses en lugar de aplicarse a uno concreto.
  bool get isRecurringTemplate => monthKey == null;

  BudgetEntity copyWith({
    String? categoryId,
    bool clearCategory = false,
    String? monthKey,
    bool clearMonth = false,
    int? limitCents,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return BudgetEntity(
      id: id,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
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
        categoryId,
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
    this.categoryName,
    this.categoryIconCode,
    this.categoryColor,
  });

  final BudgetEntity budget;
  final int spentCents;
  final String monthKey;
  final String? categoryName;
  final int? categoryIconCode;
  final int? categoryColor;

  int get limitCents => budget.limitCents;

  /// Lo que queda por gastar. Negativo si se paso.
  int get remainingCents => limitCents - spentCents;

  bool get isOverspent => spentCents > limitCents;

  /// Fraccion consumida SIN recortar: puede pasar de 1.0 para poder decir
  /// "llevas un 140 % del presupuesto".
  double get ratio => limitCents <= 0 ? 0 : spentCents / limitCents;

  /// Fraccion recortada a `[0, 1]`, para barras de progreso.
  double get clampedRatio => ratio.clamp(0.0, 1.0);

  int get percent => (ratio * 100).round();

  String get displayName => categoryName ?? 'Presupuesto global';

  @override
  List<Object?> get props => <Object?>[
        budget,
        spentCents,
        monthKey,
        categoryName,
        categoryIconCode,
        categoryColor,
      ];
}
