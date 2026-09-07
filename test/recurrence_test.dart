import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/domain/entities/recurring_rule_entity.dart';
import 'package:hannahswalletapp/domain/entities/transaction_entity.dart';

RecurringRuleEntity _rule({
  required RecurrenceFrequency frequency,
  int interval = 1,
  required DateTime next,
}) {
  final DateTime now = DateTime(2026);
  return RecurringRuleEntity(
    id: 'r1',
    walletId: 'w1',
    type: TransactionType.expense,
    amountCents: 1000,
    frequency: frequency,
    intervalCount: interval,
    nextRunAt: next,
    createdAt: now,
    updatedAt: now,
  );
}

/// Pruebas del calculo de la siguiente repeticion.
///
/// El caso que de verdad importa es el mensual a final de mes: si se resuelve
/// mal, una nomina del dia 31 se va saltando meses o cae en el dia 1 del
/// siguiente, y el usuario se encuentra apuntes en fechas que no puso.
void main() {
  group('advanceFrom diario y semanal', () {
    test('suma dias', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.daily,
        next: DateTime(2026, 8, 20),
      );
      expect(r.advanceFrom(DateTime(2026, 8, 20)), DateTime(2026, 8, 21));
    });

    test('respeta el intervalo', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        next: DateTime(2026, 8, 20),
      );
      expect(r.advanceFrom(DateTime(2026, 8, 20)), DateTime(2026, 9, 3));
    });
  });

  group('advanceFrom mensual', () {
    test('avanza un mes normal', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 8, 15),
      );
      expect(r.advanceFrom(DateTime(2026, 8, 15)), DateTime(2026, 9, 15));
    });

    test('recorta el dia 31 al ultimo dia de un mes de 30', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 8, 31),
      );
      // Septiembre tiene 30 dias: sin recorte, DateTime(2026, 9, 31)
      // desbordaria al 1 de octubre y el recibo saltaria de mes.
      expect(r.advanceFrom(DateTime(2026, 8, 31)), DateTime(2026, 9, 30));
    });

    test('recorta al 28 en febrero de un ano no bisiesto', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 1, 30),
      );
      expect(r.advanceFrom(DateTime(2026, 1, 30)), DateTime(2026, 2, 28));
    });

    test('llega al 29 en febrero bisiesto', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2028, 1, 31),
      );
      expect(r.advanceFrom(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    });

    test('cruza el cambio de ano', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 12, 5),
      );
      expect(r.advanceFrom(DateTime(2026, 12, 5)), DateTime(2027, 1, 5));
    });

    test('conserva la hora del dia', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 8, 10, 9, 30),
      );
      final DateTime next = r.advanceFrom(DateTime(2026, 8, 10, 9, 30));
      expect(next.hour, 9);
      expect(next.minute, 30);
    });
  });

  group('advanceFrom anual', () {
    test('suma doce meses', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.yearly,
        next: DateTime(2026, 8, 20),
      );
      expect(r.advanceFrom(DateTime(2026, 8, 20)), DateTime(2027, 8, 20));
    });

    test('un 29 de febrero cae en el 28 del ano siguiente', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.yearly,
        next: DateTime(2028, 2, 29),
      );
      expect(r.advanceFrom(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });
  });

  group('secuencia larga', () {
    test('un mensual del dia 31 no se desvia tras un ano', () {
      final RecurringRuleEntity r = _rule(
        frequency: RecurrenceFrequency.monthly,
        next: DateTime(2026, 1, 31),
      );

      DateTime cursor = DateTime(2026, 1, 31);
      final List<int> dias = <int>[];
      for (int i = 0; i < 12; i++) {
        cursor = r.advanceFrom(cursor);
        dias.add(cursor.day);
      }

      // Nota de diseno consciente: una vez recortado a 28 en febrero, la serie
      // sigue desde ese dia (no "recuerda" el 31 original). Es el
      // comportamiento previsible con una sola columna `next_run_at`, y el
      // usuario siempre puede reajustar la fecha de la regla.
      expect(dias.first, 28);
      expect(dias.every((int d) => d >= 28), isTrue);
      expect(cursor.year, 2027);
    });
  });
}
