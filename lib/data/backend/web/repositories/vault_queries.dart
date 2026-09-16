import 'package:intl/intl.dart';

import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/analytics.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../../domain/entities/category_entity.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../../domain/entities/wallet_entity.dart';
import '../../../../domain/services/budget_planner.dart';
import '../vault_data.dart';

/// Las mismas agregaciones que hace SQLite en la versión nativa, resueltas en
/// Dart sobre las colecciones en memoria.
///
/// Que esto sea viable no es casualidad: son finanzas personales, con miles de
/// filas, no millones. Recorrer 5 000 movimientos para sumarlos cuesta menos de
/// un milisegundo, y a cambio la bóveda puede estar cifrada de extremo a
/// extremo, cosa imposible si hubiese que consultarla con SQL.
///
/// Cada funcion replica DELIBERADAMENTE la semantica de su consulta SQL
/// equivalente (ver `database_schema.dart`), incluidas las reglas sutiles:
/// las transferencias no alteran el patrimonio, los borrados logicos no
/// cuentan y las carteras archivadas quedan fuera de los totales.
abstract final class VaultQueries {
  /// Movimientos vivos de carteras activas.
  static Iterable<TransactionEntity> liveTransactions(VaultData d) {
    return d.transactions.values.where((TransactionEntity t) {
      if (t.isDeleted) return false;
      final WalletEntity? w = d.wallets[t.walletId];
      return w != null && !w.isArchived;
    });
  }

  static int byRecency(TransactionEntity a, TransactionEntity b) {
    final int byDate = b.occurredAt.compareTo(a.occurredAt);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  }

  static TransactionView toView(VaultData d, TransactionEntity t) {
    final WalletEntity? wallet = d.wallets[t.walletId];
    final CategoryEntity? category =
        t.categoryId == null ? null : d.categories[t.categoryId];
    final WalletEntity? destination =
        t.transferWalletId == null ? null : d.wallets[t.transferWalletId];

    return TransactionView(
      transaction: t,
      walletName: wallet?.name ?? 'Cartera',
      walletColor: wallet?.colorValue ?? 0xFF7A6A61,
      categoryName: category?.name,
      categoryIconCode: category?.iconCode,
      categoryColor: category?.colorValue,
      transferWalletName: destination?.name,
    );
  }

  /// Saldo acumulado histórico.
  ///
  /// Sin filtro de fecha, partiendo del saldo inicial de cada cartera y con las
  /// transferencias fuera: mover dinero entre carteras propias no crea ni
  /// destruye patrimonio.
  static int lifetimeBalance(VaultData d) {
    int total = 0;
    for (final WalletEntity w in d.wallets.values) {
      if (!w.isArchived) total += w.initialBalanceCents;
    }
    for (final TransactionEntity t in liveTransactions(d)) {
      switch (t.type) {
        case TransactionType.income:
          total += t.amountCents;
        case TransactionType.expense:
          total -= t.amountCents;
        case TransactionType.transfer:
          break;
      }
    }
    return total;
  }

  /// Saldo de una cartera: sus movimientos mas las transferencias entrantes.
  static int walletBalance(VaultData d, WalletEntity wallet) {
    int total = wallet.initialBalanceCents;
    for (final TransactionEntity t in d.transactions.values) {
      if (t.isDeleted) continue;
      if (t.walletId == wallet.id) {
        switch (t.type) {
          case TransactionType.income:
            total += t.amountCents;
          case TransactionType.expense:
          case TransactionType.transfer:
            total -= t.amountCents;
        }
      } else if (t.transferWalletId == wallet.id &&
          t.type == TransactionType.transfer) {
        total += t.amountCents;
      }
    }
    return total;
  }

  static PeriodTotals totals(VaultData d, DateRange range) {
    int income = 0;
    int expense = 0;
    for (final TransactionEntity t in liveTransactions(d)) {
      if (!range.contains(t.occurredAt)) continue;
      switch (t.type) {
        case TransactionType.income:
          income += t.amountCents;
        case TransactionType.expense:
          expense += t.amountCents;
        case TransactionType.transfer:
          break;
      }
    }
    return PeriodTotals(incomeCents: income, expenseCents: expense);
  }

  static List<CategorySpending> expenseByCategory(
    VaultData d,
    DateRange range,
  ) {
    final Map<String?, int> totals = <String?, int>{};
    final Map<String?, int> counts = <String?, int>{};

    for (final TransactionEntity t in liveTransactions(d)) {
      if (t.type != TransactionType.expense) continue;
      if (!range.contains(t.occurredAt)) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amountCents;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
    }

    final List<CategorySpending> result = totals.entries.map((MapEntry<String?, int> e) {
      final CategoryEntity? c = e.key == null ? null : d.categories[e.key];
      return CategorySpending(
        categoryId: e.key,
        categoryName: c?.name ?? 'Sin categoría',
        iconCode: c?.iconCode ?? 0xe148,
        colorValue: c?.colorValue ?? 0xFF7A6A61,
        totalCents: e.value,
        entryCount: counts[e.key] ?? 0,
      );
    }).toList()
      ..sort((CategorySpending a, CategorySpending b) =>
          b.totalCents.compareTo(a.totalCents));

    return result;
  }

  /// Serie de barras. Misma ventana que la versión SQL: 7 días, 8 semanas, los
  /// 12 meses del año o 5 años.
  static List<SeriesBucket> series(
    VaultData d,
    StatsPeriod period,
    DateTime anchor,
  ) {
    final List<DateTime> starts = _bucketStarts(period, anchor);
    if (starts.isEmpty) return const <SeriesBucket>[];

    final DateTime now = AppClock.now();
    final List<DateTime> ends = starts
        .map((DateTime start) => _bucketEnd(period, start))
        .toList(growable: false);
    final List<int> income = List<int>.filled(starts.length, 0);
    final List<int> expense = List<int>.filled(starts.length, 0);

    // Una sola pasada por el historial: cada movimiento cae en su tramo por
    // búsqueda binaria. Antes se recorría entero una vez por tramo (hasta 12),
    // y esto se recalcula tras cada cambio aunque Estadísticas no esté a la
    // vista.
    for (final TransactionEntity t in liveTransactions(d)) {
      if (t.type == TransactionType.transfer) continue;
      final int i = _bucketIndex(starts, t.occurredAt);
      if (i < 0 || !t.occurredAt.isBefore(ends[i])) continue;
      if (t.type == TransactionType.income) {
        income[i] += t.amountCents;
      } else {
        expense[i] += t.amountCents;
      }
    }

    return <SeriesBucket>[
      for (int i = 0; i < starts.length; i++)
        SeriesBucket(
          label: _bucketLabel(period, starts[i]),
          start: starts[i],
          incomeCents: income[i],
          expenseCents: expense[i],
          isCurrent: !now.isBefore(starts[i]) && now.isBefore(ends[i]),
        ),
    ];
  }

  /// Último tramo que empieza en [when] o antes; `-1` si es anterior a todos.
  /// [starts] va en orden ascendente.
  static int _bucketIndex(List<DateTime> starts, DateTime when) {
    int low = 0;
    int high = starts.length - 1;
    int found = -1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (starts[mid].isAfter(when)) {
        high = mid - 1;
      } else {
        found = mid;
        low = mid + 1;
      }
    }
    return found;
  }

  /// Presupuestos vigentes del mes con su consumo.
  ///
  /// Aquí solo se reúne el gasto; qué presupuesto manda lo decide
  /// `BudgetPlanner`, el mismo que usa la versión nativa.
  static List<BudgetProgress> budgetProgress(VaultData d, DateTime month) {
    final DateRange range = DateRange.monthOf(month);
    final Map<String?, int> spent = <String?, int>{};
    for (final TransactionEntity t in liveTransactions(d)) {
      if (t.type != TransactionType.expense) continue;
      if (!range.contains(t.occurredAt)) continue;
      spent[t.categoryId] = (spent[t.categoryId] ?? 0) + t.amountCents;
    }

    return BudgetPlanner.progress(
      budgets: d.budgets.values,
      categories: d.categories,
      spentByCategory: spent,
      monthKey: range.monthKey,
    );
  }

  // --- Ayudas de los intervalos de la serie ---

  static List<DateTime> _bucketStarts(StatsPeriod period, DateTime anchor) {
    switch (period) {
      case StatsPeriod.day:
        final DateTime end = DateTime(anchor.year, anchor.month, anchor.day);
        return List<DateTime>.generate(
          7,
          (int i) => end.subtract(Duration(days: 6 - i)),
        );
      case StatsPeriod.week:
        final DateTime week = DateRange.of(StatsPeriod.week, anchor).start;
        return List<DateTime>.generate(
          8,
          (int i) => week.subtract(Duration(days: 7 * (7 - i))),
        );
      case StatsPeriod.month:
        return List<DateTime>.generate(
          12,
          (int i) => DateTime(anchor.year, i + 1),
        );
      case StatsPeriod.year:
        return List<DateTime>.generate(
          5,
          (int i) => DateTime(anchor.year - 4 + i),
        );
    }
  }

  static DateTime _bucketEnd(StatsPeriod period, DateTime start) {
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

  static String _bucketLabel(StatsPeriod period, DateTime start) {
    switch (period) {
      case StatsPeriod.day:
        return DateFormat('E', AppDates.locale)
            .format(start)
            .substring(0, 1)
            .toUpperCase();
      case StatsPeriod.week:
        return DateFormat('d/M', AppDates.locale).format(start);
      case StatsPeriod.month:
        return DateFormat('MMM', AppDates.locale).format(start);
      case StatsPeriod.year:
        return DateFormat('yy', AppDates.locale).format(start);
    }
  }
}
