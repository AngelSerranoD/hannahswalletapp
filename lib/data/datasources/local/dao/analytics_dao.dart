import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/analytics.dart';
import '../../../../domain/entities/category_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Consultas de solo lectura para cabecera y estadísticas.
///
/// Toda la agregacion se hace en SQL, nunca en Dart. Traer 5000 movimientos
/// para sumarlos en un `fold` obliga a instanciar 5000 objetos y recorrerlos
/// en el hilo de UI; el mismo `SUM()` dentro de SQLite lo resuelve sobre el
/// índice sin materializar una sola fila.
class AnalyticsDao {
  AnalyticsDao(this._provider);

  final DatabaseProvider _provider;

  /// Saldo acumulado histórico. Ver [DatabaseSchema.queryLifetimeBalance]
  /// para el detalle de por que no lleva filtro de fecha.
  Future<int> lifetimeBalance() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows =
        await db.rawQuery(DatabaseSchema.queryLifetimeBalance);
    return asInt(rows.first['balance_cents']);
  }

  Future<PeriodTotals> totalsForRange(DateRange range) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      DatabaseSchema.queryPeriodTotals,
      <Object?>[range.startMs, range.endMs],
    );
    final Map<String, Object?> row = rows.first;
    return PeriodTotals(
      incomeCents: asInt(row['income_cents']),
      expenseCents: asInt(row['expense_cents']),
    );
  }

  Future<List<CategorySpending>> expenseByCategory(DateRange range) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      DatabaseSchema.queryExpenseByCategory,
      <Object?>[range.startMs, range.endMs],
    );
    return rows
        .map((Map<String, Object?> m) => CategorySpending(
              categoryId: asStringOrNull(m['category_id']),
              categoryName:
                  asStringOrNull(m['category_name']) ?? 'Sin categoría',
              iconCode: asInt(m['icon_code'], fallback: 0xe148),
              colorValue: asInt(m['color_value'], fallback: 0xFF7A6A61),
              totalCents: asInt(m['total_cents']),
              entryCount: asInt(m['entry_count']),
            ))
        .toList(growable: false);
  }

  /// Serie de barras del periodo seleccionado.
  ///
  /// La gráfica no muestra UN periodo, sino la secuencia de los últimos, que
  /// es lo que permite ver una tendencia: 7 días, 8 semanas, los 12 meses del
  /// año o los últimos 5 años.
  ///
  /// La agrupación la hace SQLite con `strftime` sobre `occurred_at`. El
  /// modificador `'localtime'` es imprescindible: sin el, un gasto de las
  /// 00:30 se contaria en el día anterior para cualquiera al este de Greenwich.
  Future<List<SeriesBucket>> series(StatsPeriod period, DateTime anchor) async {
    final Database db = await _provider.database();
    final (List<DateTime> starts, String sqlFormat, String Function(DateTime) labelOf) =
        _bucketPlan(period, anchor);

    if (starts.isEmpty) return const <SeriesBucket>[];

    final DateTime from = starts.first;
    final DateTime to = _bucketEnd(period, starts.last);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        strftime('$sqlFormat', t.occurred_at / 1000, 'unixepoch', 'localtime') AS bucket,
        COALESCE(SUM(CASE WHEN t.type = 'income'  THEN t.amount_cents END), 0) AS income_cents,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_cents END), 0) AS expense_cents
      FROM "transactions" t
      JOIN wallets w ON w.id = t.wallet_id
      WHERE t.is_deleted = 0
        AND w.is_archived = 0
        AND t.occurred_at >= ?
        AND t.occurred_at <  ?
      GROUP BY bucket
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    final Map<String, (int, int)> byBucket = <String, (int, int)>{
      for (final Map<String, Object?> r in rows)
        (r['bucket'] as String?) ?? '':
            (asInt(r['income_cents']), asInt(r['expense_cents'])),
    };

    final DateTime now = DateTime.now();
    return starts.map((DateTime start) {
      final String key = _bucketKey(period, start);
      final (int, int) values = byBucket[key] ?? (0, 0);
      return SeriesBucket(
        label: labelOf(start),
        start: start,
        incomeCents: values.$1,
        expenseCents: values.$2,
        isCurrent: !now.isBefore(start) && now.isBefore(_bucketEnd(period, start)),
      );
    }).toList(growable: false);
  }

  /// Cuantos periodos se pintan, con que formato los agrupa SQLite y como se
  /// etiqueta cada uno en el eje X.
  (List<DateTime>, String, String Function(DateTime)) _bucketPlan(
    StatsPeriod period,
    DateTime anchor,
  ) {
    switch (period) {
      case StatsPeriod.day:
        final DateTime end = DateTime(anchor.year, anchor.month, anchor.day);
        return (
          List<DateTime>.generate(
            7,
            (int i) => end.subtract(Duration(days: 6 - i)),
          ),
          '%Y-%m-%d',
          (DateTime d) => AppDates.fmt('E').format(d).substring(0, 1).toUpperCase(),
        );

      case StatsPeriod.week:
        final DateTime thisWeek = DateRange.of(StatsPeriod.week, anchor).start;
        return (
          List<DateTime>.generate(
            8,
            (int i) => thisWeek.subtract(Duration(days: 7 * (7 - i))),
          ),
          '%Y-%W',
          (DateTime d) => AppDates.fmt('d/M').format(d),
        );

      case StatsPeriod.month:
        return (
          List<DateTime>.generate(12, (int i) => DateTime(anchor.year, i + 1)),
          '%Y-%m',
          (DateTime d) => AppDates.fmt('MMM').format(d),
        );

      case StatsPeriod.year:
        return (
          List<DateTime>.generate(5, (int i) => DateTime(anchor.year - 4 + i)),
          '%Y',
          (DateTime d) => AppDates.fmt('yy').format(d),
        );
    }
  }

  /// Reproduce en Dart la clave que genera `strftime` en SQLite.
  String _bucketKey(StatsPeriod period, DateTime start) {
    switch (period) {
      case StatsPeriod.day:
        return AppDates.fmt('yyyy-MM-dd').format(start);
      case StatsPeriod.week:
        // '%W' cuenta semanas empezando en lunes, con la semana 00 para los
        // días anteriores al primer lunes del año. `dayOfYear` replica
        // exactamente esa aritmetica.
        final int dayOfYear =
            start.difference(DateTime(start.year)).inDays + 1;
        final int firstWeekday = DateTime(start.year).weekday % 7; // dom=0
        final int week = ((dayOfYear + firstWeekday - 1) / 7).floor();
        return '${start.year.toString().padLeft(4, '0')}-'
            '${week.toString().padLeft(2, '0')}';
      case StatsPeriod.month:
        return AppDates.fmt('yyyy-MM').format(start);
      case StatsPeriod.year:
        return AppDates.fmt('yyyy').format(start);
    }
  }

  DateTime _bucketEnd(StatsPeriod period, DateTime start) {
    switch (period) {
      case StatsPeriod.day:
        return start.add(const Duration(days: 1));
      case StatsPeriod.week:
        return start.add(const Duration(days: 7));
      case StatsPeriod.month:
        return DateTime(start.year, start.month + 1);
      case StatsPeriod.year:
        return DateTime(start.year + 1);
    }
  }

  /// Media de gasto diario del mes en curso. La usa la tarjeta de ritmo.
  Future<int> averageDailyExpense(DateTime month) async {
    final DateRange range = DateRange.monthOf(month);
    final PeriodTotals totals = await totalsForRange(range);
    final DateTime now = DateTime.now();
    final int elapsedDays = range.contains(now)
        ? now.day
        : range.end.difference(range.start).inDays;
    return elapsedDays <= 0 ? 0 : (totals.expenseCents / elapsedDays).round();
  }
}
