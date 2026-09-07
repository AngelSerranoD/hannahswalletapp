import 'package:equatable/equatable.dart';

/// Totales de ingresos y gastos de un intervalo.
class PeriodTotals extends Equatable {
  const PeriodTotals({required this.incomeCents, required this.expenseCents});

  const PeriodTotals.zero() : incomeCents = 0, expenseCents = 0;

  final int incomeCents;
  final int expenseCents;

  /// Ahorro del periodo. Negativo si se gasto mas de lo que entró.
  int get netCents => incomeCents - expenseCents;

  /// Porcentaje de lo ingresado que se ha logrado no gastar.
  double get savingsRate =>
      incomeCents <= 0 ? 0 : (netCents / incomeCents).clamp(-1.0, 1.0);

  @override
  List<Object?> get props => <Object?>[incomeCents, expenseCents];
}

/// Una barra de la gráfica: un día, una semana, un mes o un año.
class SeriesBucket extends Equatable {
  const SeriesBucket({
    required this.label,
    required this.start,
    required this.incomeCents,
    required this.expenseCents,
    this.isCurrent = false,
  });

  /// Etiqueta corta del eje X ("L", "12", "ene", "2026").
  final String label;
  final DateTime start;
  final int incomeCents;
  final int expenseCents;

  /// Resalta el periodo en curso dentro de la gráfica.
  final bool isCurrent;

  int get netCents => incomeCents - expenseCents;

  @override
  List<Object?> get props =>
      <Object?>[label, start, incomeCents, expenseCents, isCurrent];
}

/// Todo lo que la cabecera del dashboard necesita, resuelto de una vez.
///
/// Se agrupa en un único objeto para que la cabecera se pinte con UNA lectura
/// coherente. Si el saldo, los totales del mes y el presupuesto llegasen por
/// tres providers independientes, un guardado a medias podría mostrar el saldo
/// ya actualizado junto a un presupuesto todavia sin refrescar.
class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.lifetimeBalanceCents,
    required this.monthTotals,
    required this.currencyCode,
    this.budgetLimitCents,
    this.budgetSpentCents,
  });

  /// Saldo acumulado desde siempre. NO se reinicia cada mes.
  final int lifetimeBalanceCents;
  final PeriodTotals monthTotals;
  final String currencyCode;

  /// `null` si el usuario no ha definido presupuesto global para este mes.
  final int? budgetLimitCents;
  final int? budgetSpentCents;

  bool get hasBudget => budgetLimitCents != null && budgetLimitCents! > 0;

  /// Fraccion del presupuesto global consumida. 0 si no hay presupuesto.
  double get budgetRatio {
    final int? limit = budgetLimitCents;
    final int? spent = budgetSpentCents;
    if (limit == null || spent == null || limit <= 0) return 0;
    return spent / limit;
  }

  @override
  List<Object?> get props => <Object?>[
        lifetimeBalanceCents,
        monthTotals,
        currencyCode,
        budgetLimitCents,
        budgetSpentCents,
      ];
}
