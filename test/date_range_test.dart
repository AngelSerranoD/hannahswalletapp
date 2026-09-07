import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/utils/date_range.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pruebas de los intervalos que gobiernan estadisticas y presupuestos.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));

  group('DateRange.of', () {
    test('el dia va de medianoche a medianoche', () {
      final DateRange r =
          DateRange.of(StatsPeriod.day, DateTime(2026, 8, 20, 15, 42));
      expect(r.start, DateTime(2026, 8, 20));
      expect(r.end, DateTime(2026, 8, 21));
    });

    test('la semana empieza en lunes', () {
      // 20/08/2026 es jueves; su semana arranca el lunes 17.
      final DateRange r = DateRange.of(StatsPeriod.week, DateTime(2026, 8, 20));
      expect(r.start, DateTime(2026, 8, 17));
      expect(r.start.weekday, DateTime.monday);
      expect(r.end, DateTime(2026, 8, 24));
    });

    test('el mes cubre el mes natural completo', () {
      final DateRange r = DateRange.of(StatsPeriod.month, DateTime(2026, 8, 20));
      expect(r.start, DateTime(2026, 8));
      expect(r.end, DateTime(2026, 9));
    });

    test('el ano cubre el ano natural', () {
      final DateRange r = DateRange.of(StatsPeriod.year, DateTime(2026, 8, 20));
      expect(r.start, DateTime(2026));
      expect(r.end, DateTime(2027));
    });
  });

  group('semiapertura del intervalo', () {
    test('incluye el inicio y excluye el final', () {
      final DateRange r = DateRange.monthOf(DateTime(2026, 8, 10));
      expect(r.contains(DateTime(2026, 8)), isTrue);
      expect(r.contains(DateTime(2026, 8, 31, 23, 59, 59, 999)), isTrue);
      // El primer instante de septiembre ya NO pertenece a agosto: es lo que
      // evita contar dos veces un movimiento justo en la frontera.
      expect(r.contains(DateTime(2026, 9)), isFalse);
    });
  });

  group('DateRange.shift', () {
    test('retrocede de mes cruzando el cambio de ano', () {
      final DateRange enero = DateRange.monthOf(DateTime(2026, 1, 15));
      final DateRange previo = enero.shift(StatsPeriod.month, -1);
      expect(previo.start, DateTime(2025, 12));
      expect(previo.end, DateTime(2026));
    });

    test('avanza semanas completas', () {
      final DateRange semana = DateRange.of(StatsPeriod.week, DateTime(2026, 8, 20));
      final DateRange siguiente = semana.shift(StatsPeriod.week, 1);
      expect(siguiente.start, DateTime(2026, 8, 24));
    });
  });

  group('monthKey', () {
    test('rellena el mes con cero a la izquierda', () {
      expect(DateRange.monthKeyOf(DateTime(2026, 3, 9)), '2026-03');
      expect(DateRange.monthKeyOf(DateTime(2026, 11, 30)), '2026-11');
    });

    test('el orden alfabetico coincide con el cronologico', () {
      // De esto depende el `ORDER BY month_key DESC` de BudgetDao.
      final List<String> keys = <String>[
        DateRange.monthKeyOf(DateTime(2026, 9)),
        DateRange.monthKeyOf(DateTime(2026, 10)),
        DateRange.monthKeyOf(DateTime(2027)),
      ];
      final List<String> ordenadas = List<String>.of(keys)..sort();
      expect(ordenadas, keys);
    });
  });
}
