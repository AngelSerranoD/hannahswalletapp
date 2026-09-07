import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/utils/date_range.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/mascot_state.dart';
import '../../domain/entities/recurring_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/wallet_entity.dart';
import '../widgets/mascot/kitty_mascot_controller.dart';

/// Providers de lectura.
///
/// TODOS empiezan observando [dataRevisionProvider]. Esa linea, que parece
/// inerte porque no se usa el valor, es lo que hace que la pantalla se
/// actualice sola: al guardar un gasto el repositorio avisa al bus, el
/// contador sube y Riverpod recalcula estos providers.
///
/// Riverpod conserva el valor anterior mientras recalcula (`AsyncLoading` con
/// dato previo), así que la lista no parpadea a vacio en cada refresco.

// ------------------------------------------------------------- Dashboard

final FutureProvider<DashboardSummary> dashboardSummaryProvider =
    FutureProvider<DashboardSummary>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(analyticsRepositoryProvider).getDashboardSummary();
});

/// Número de movimientos que carga el dashboard de una vez.
final StateProvider<int> dashboardPageSizeProvider =
    StateProvider<int>((Ref ref) => 60);

final FutureProvider<List<TransactionView>> recentTransactionsProvider =
    FutureProvider<List<TransactionView>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  final int limit = ref.watch(dashboardPageSizeProvider);
  return ref.watch(transactionRepositoryProvider).getRecent(limit: limit);
});

/// Movimientos agrupados por día, listos para la `ListView` del dashboard.
///
/// La agrupación se hace aquí y no en el `build` del widget para que no se
/// repita en cada frame de scroll.
final Provider<List<TransactionDayGroup>> groupedTransactionsProvider =
    Provider<List<TransactionDayGroup>>((Ref ref) {
  final List<TransactionView> items =
      ref.watch(recentTransactionsProvider).valueOrNull ??
          const <TransactionView>[];

  final Map<int, List<TransactionView>> byDay = <int, List<TransactionView>>{};
  for (final TransactionView view in items) {
    final int key = AppDates.dayKey(view.transaction.occurredAt);
    byDay.putIfAbsent(key, () => <TransactionView>[]).add(view);
  }

  final List<int> keys = byDay.keys.toList()..sort((int a, int b) => b.compareTo(a));

  return keys.map((int key) {
    final List<TransactionView> dayItems = byDay[key]!;
    int income = 0;
    int expense = 0;
    for (final TransactionView v in dayItems) {
      switch (v.transaction.type) {
        case TransactionType.income:
          income += v.transaction.amountCents;
        case TransactionType.expense:
          expense += v.transaction.amountCents;
        case TransactionType.transfer:
          break;
      }
    }
    return TransactionDayGroup(
      day: DateTime.fromMillisecondsSinceEpoch(key),
      items: dayItems,
      incomeCents: income,
      expenseCents: expense,
    );
  }).toList(growable: false);
});

/// Un día de la lista del dashboard, con su cabecera y su neto.
class TransactionDayGroup {
  const TransactionDayGroup({
    required this.day,
    required this.items,
    required this.incomeCents,
    required this.expenseCents,
  });

  final DateTime day;
  final List<TransactionView> items;
  final int incomeCents;
  final int expenseCents;

  int get netCents => incomeCents - expenseCents;
}

// --------------------------------------------------------------- Carteras

final FutureProvider<List<WalletWithBalance>> walletsWithBalanceProvider =
    FutureProvider<List<WalletWithBalance>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(walletRepositoryProvider).getWalletsWithBalance();
});

final FutureProvider<List<WalletEntity>> walletsProvider =
    FutureProvider<List<WalletEntity>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(walletRepositoryProvider).getWallets();
});

// ------------------------------------------------------------- Categorías

final FutureProviderFamily<List<CategoryEntity>, TransactionType?>
    categoriesProvider =
    FutureProvider.family<List<CategoryEntity>, TransactionType?>(
        (Ref ref, TransactionType? type) async {
  ref.watch(dataRevisionProvider);
  // Los traspasos no llevan categoría: se pide la lista de gastos para no
  // devolver una lista vacia que dejaria el selector en blanco.
  final TransactionType? effective =
      type == TransactionType.transfer ? null : type;
  return ref.watch(categoryRepositoryProvider).getCategories(type: effective);
});

// ----------------------------------------------------------- Presupuestos

/// Mes que se esta consultando en la pantalla de presupuestos.
final StateProvider<DateTime> budgetMonthProvider =
    StateProvider<DateTime>((Ref ref) => DateTime.now());

final FutureProviderFamily<List<BudgetProgress>, DateTime>
    budgetProgressProvider =
    FutureProvider.family<List<BudgetProgress>, DateTime>(
        (Ref ref, DateTime month) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(budgetRepositoryProvider).getProgressForMonth(month);
});

// -------------------------------------------------------------- Recurrentes

final FutureProvider<List<RecurringRuleEntity>> recurringRulesProvider =
    FutureProvider<List<RecurringRuleEntity>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(recurringRepositoryProvider).getAll();
});

// ----------------------------------------------------------- Estadísticas

final StateProvider<StatsPeriod> statsPeriodProvider =
    StateProvider<StatsPeriod>((Ref ref) => StatsPeriod.month);

/// Fecha de referencia del periodo mostrado. Cambiarla es "mes anterior".
final StateProvider<DateTime> statsAnchorProvider =
    StateProvider<DateTime>((Ref ref) => DateTime.now());

final Provider<DateRange> statsRangeProvider = Provider<DateRange>((Ref ref) {
  return DateRange.of(
    ref.watch(statsPeriodProvider),
    ref.watch(statsAnchorProvider),
  );
});

final FutureProvider<PeriodTotals> statsTotalsProvider =
    FutureProvider<PeriodTotals>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(analyticsRepositoryProvider).getTotals(ref.watch(statsRangeProvider));
});

final FutureProvider<List<SeriesBucket>> statsSeriesProvider =
    FutureProvider<List<SeriesBucket>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(analyticsRepositoryProvider).getSeries(
        ref.watch(statsPeriodProvider),
        ref.watch(statsAnchorProvider),
      );
});

final FutureProvider<List<CategorySpending>> statsByCategoryProvider =
    FutureProvider<List<CategorySpending>>((Ref ref) async {
  ref.watch(dataRevisionProvider);
  return ref
      .watch(analyticsRepositoryProvider)
      .getExpenseByCategory(ref.watch(statsRangeProvider));
});

// ---------------------------------------------------------------- Mascota

/// Humor del gato, derivado del presupuesto global del mes.
///
/// Es un provider aparte y no un campo del dashboard para que la mascota se
/// pueda observar desde cualquier pantalla sin arrastrar el resto del resumen.
final Provider<MascotState> mascotStateProvider = Provider<MascotState>((Ref ref) {
  final DashboardSummary? summary =
      ref.watch(dashboardSummaryProvider).valueOrNull;
  if (summary == null || !summary.hasBudget) return MascotState.neutral();
  return MascotState.fromRatio(summary.budgetRatio);
});

/// Controlador único de la mascota, compartido por toda la app.
///
/// Vive en el contenedor y no en el `State` del dashboard porque cualquier
/// pantalla (el formulario de gasto, por ejemplo) tiene que poder dispararle
/// la celebracion, y porque así el gato no reinicia su animación cada vez que
/// se reconstruye la lista.
final Provider<KittyMascotController> kittyControllerProvider =
    Provider<KittyMascotController>((Ref ref) {
  final KittyMascotController controller = KittyMascotController();

  // El enlace que pedia el Modulo 4: el porcentaje de presupuesto consumido
  // alimenta `budgetHealth`, y al cruzar el 90 % el propio controlador dispara
  // la alerta.
  ref.listen<MascotState>(
    mascotStateProvider,
    (MascotState? previous, MascotState next) => controller.applyState(next),
    fireImmediately: true,
  );

  ref.onDispose(controller.dispose);
  return controller;
});
