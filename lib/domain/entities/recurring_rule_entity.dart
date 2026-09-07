import 'package:equatable/equatable.dart';

import 'transaction_entity.dart';

/// Cada cuanto se repite un movimiento automático.
enum RecurrenceFrequency {
  daily('daily', 'Diaria'),
  weekly('weekly', 'Semanal'),
  monthly('monthly', 'Mensual'),
  yearly('yearly', 'Anual');

  const RecurrenceFrequency(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static RecurrenceFrequency fromDb(String value) => values.firstWhere(
        (RecurrenceFrequency f) => f.dbValue == value,
        orElse: () => RecurrenceFrequency.monthly,
      );
}

/// Plantilla de un movimiento que se repite: nómina, alquiler, suscripciones.
///
/// Sin esto, el "saldo acumulado histórico" de la cabecera solo es fiable si
/// el usuario se acuerda de apuntar la nómina todos los meses. Las reglas
/// generan los movimientos que falten al abrir la app (ver
/// `RecurringService.materializeDue`), incluso si estuvo semanas sin abrirla.
class RecurringRuleEntity extends Equatable {
  const RecurringRuleEntity({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amountCents,
    required this.frequency,
    required this.nextRunAt,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.note,
    this.intervalCount = 1,
    this.endAt,
    this.lastRunAt,
    this.isActive = true,
    this.isDeleted = false,
  });

  final String id;
  final String walletId;
  final String? categoryId;
  final TransactionType type;
  final int amountCents;
  final String? note;
  final RecurrenceFrequency frequency;

  /// Multiplicador del periodo: `frequency = weekly` + `intervalCount = 2`
  /// significa "cada dos semanas".
  final int intervalCount;
  final DateTime nextRunAt;
  final DateTime? endAt;
  final DateTime? lastRunAt;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Calcula la siguiente fecha a partir de [from].
  ///
  /// El caso peliagudo es el mensual: si la regla nace un 31 y el mes siguiente
  /// tiene 30 días, `DateTime(y, m + 1, 31)` desbordaria al 1 del mes
  /// posterior y la nómina saltaría de mes. Se recorta al último día real.
  DateTime advanceFrom(DateTime from) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return from.add(Duration(days: intervalCount));
      case RecurrenceFrequency.weekly:
        return from.add(Duration(days: 7 * intervalCount));
      case RecurrenceFrequency.monthly:
        return _addMonthsClamped(from, intervalCount);
      case RecurrenceFrequency.yearly:
        return _addMonthsClamped(from, 12 * intervalCount);
    }
  }

  static DateTime _addMonthsClamped(DateTime from, int months) {
    final int targetMonthIndex = from.month - 1 + months;
    final int year = from.year + (targetMonthIndex ~/ 12);
    final int month = (targetMonthIndex % 12) + 1;
    final int lastDayOfTarget = DateTime(year, month + 1, 0).day;
    final int day = from.day <= lastDayOfTarget ? from.day : lastDayOfTarget;
    return DateTime(year, month, day, from.hour, from.minute);
  }

  RecurringRuleEntity copyWith({
    String? walletId,
    String? categoryId,
    bool clearCategory = false,
    TransactionType? type,
    int? amountCents,
    String? note,
    RecurrenceFrequency? frequency,
    int? intervalCount,
    DateTime? nextRunAt,
    DateTime? endAt,
    bool clearEnd = false,
    DateTime? lastRunAt,
    bool? isActive,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return RecurringRuleEntity(
      id: id,
      walletId: walletId ?? this.walletId,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      note: note ?? this.note,
      frequency: frequency ?? this.frequency,
      intervalCount: intervalCount ?? this.intervalCount,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      endAt: clearEnd ? null : (endAt ?? this.endAt),
      lastRunAt: lastRunAt ?? this.lastRunAt,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        walletId,
        categoryId,
        type,
        amountCents,
        note,
        frequency,
        intervalCount,
        nextRunAt,
        endAt,
        lastRunAt,
        isActive,
        isDeleted,
        updatedAt,
      ];
}
