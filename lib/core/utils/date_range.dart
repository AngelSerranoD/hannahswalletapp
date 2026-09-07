import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Granularidad del selector de periodo de la pantalla de estadísticas.
///
/// Replica el "day / week / month / year" del original, que es lo que permite
/// leer las mismas transacciones como habito diario o como tendencia anual.
enum StatsPeriod {
  day('Día'),
  week('Semana'),
  month('Mes'),
  year('Año');

  const StatsPeriod(this.label);
  final String label;
}

/// Intervalo semiabierto `[start, end)` en hora local.
///
/// Semiabierto a proposito: con `end` exclusivo no hay que pelearse con el
/// último milisegundo del día y las consultas SQL quedan `>= ? AND < ?`, que
/// además aprovecha el índice por fecha.
class DateRange extends Equatable {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Construye el intervalo que contiene [anchor] para la granularidad dada.
  factory DateRange.of(StatsPeriod period, DateTime anchor) {
    switch (period) {
      case StatsPeriod.day:
        final DateTime s = DateTime(anchor.year, anchor.month, anchor.day);
        return DateRange(s, s.add(const Duration(days: 1)));
      case StatsPeriod.week:
        // Semana europea: lunes a domingo.
        final DateTime d = DateTime(anchor.year, anchor.month, anchor.day);
        final DateTime s = d.subtract(Duration(days: d.weekday - 1));
        return DateRange(s, s.add(const Duration(days: 7)));
      case StatsPeriod.month:
        final DateTime s = DateTime(anchor.year, anchor.month);
        return DateRange(s, DateTime(anchor.year, anchor.month + 1));
      case StatsPeriod.year:
        return DateRange(DateTime(anchor.year), DateTime(anchor.year + 1));
    }
  }

  /// Mes natural que contiene [anchor]. Es el periodo de los presupuestos.
  factory DateRange.monthOf(DateTime anchor) =>
      DateRange.of(StatsPeriod.month, anchor);

  int get startMs => start.millisecondsSinceEpoch;

  int get endMs => end.millisecondsSinceEpoch;

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// Desplaza el intervalo [delta] periodos hacia delante (o atras si negativo).
  DateRange shift(StatsPeriod period, int delta) {
    switch (period) {
      case StatsPeriod.day:
        return DateRange.of(period, start.add(Duration(days: delta)));
      case StatsPeriod.week:
        return DateRange.of(period, start.add(Duration(days: 7 * delta)));
      case StatsPeriod.month:
        return DateRange.of(period, DateTime(start.year, start.month + delta));
      case StatsPeriod.year:
        return DateRange.of(period, DateTime(start.year + delta));
    }
  }

  /// Etiqueta humana del intervalo, en espanol.
  String label(StatsPeriod period, {String locale = 'es_ES'}) {
    switch (period) {
      case StatsPeriod.day:
        return _capitalize(AppDates.fmt('EEEE d MMM y').format(start));
      case StatsPeriod.week:
        final DateTime last = end.subtract(const Duration(days: 1));
        final String a = AppDates.fmt('d MMM').format(start);
        final String b = AppDates.fmt('d MMM y').format(last);
        return '$a - $b';
      case StatsPeriod.month:
        return _capitalize(AppDates.fmt('MMMM y').format(start));
      case StatsPeriod.year:
        return AppDates.fmt('y').format(start);
    }
  }

  /// Clave `AAAA-MM` que usan los presupuestos mensuales.
  String get monthKey =>
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}';

  static String monthKeyOf(DateTime moment) => DateRange.monthOf(moment).monthKey;

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  List<Object?> get props => <Object?>[start, end];
}

/// Formateadores de fecha reutilizados por la UI.
abstract final class AppDates {
  static const String locale = 'es_ES';

  /// Formateadores ya construidos, por patron.
  ///
  /// Mismo motivo que en `Money`: `DateFormat` compila su patron al crearse, y
  /// la cabecera de cada dia de la lista lo hacia una vez por fila.
  static final Map<String, DateFormat> _cache = <String, DateFormat>{};

  static DateFormat fmt(String pattern, [String loc = locale]) =>
      _cache['$loc|$pattern'] ??= DateFormat(pattern, loc);

  static String dayHeader(DateTime day) {
    final DateTime today = _atMidnight(DateTime.now());
    final DateTime d = _atMidnight(day);
    final int diff = today.difference(d).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff == -1) return 'Mañana';
    if (diff.abs() < 7) {
      return DateRange._capitalize(AppDates.fmt('EEEE').format(d));
    }
    if (d.year == today.year) {
      return DateRange._capitalize(AppDates.fmt('EEEE d MMM').format(d));
    }
    return DateRange._capitalize(AppDates.fmt('d MMM y').format(d));
  }

  static String time(DateTime moment) =>
      AppDates.fmt('HH:mm').format(moment);

  static String shortDate(DateTime moment) =>
      AppDates.fmt('d MMM y').format(moment);

  static String fileStamp(DateTime moment) =>
      AppDates.fmt('yyyy-MM-dd_HH-mm').format(moment);

  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Clave de agrupación diaria usada por el dashboard.
  static int dayKey(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}
