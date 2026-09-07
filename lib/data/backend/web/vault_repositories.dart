import 'dart:async';

import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/analytics.dart';
import '../../../domain/entities/budget_entity.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/recurring_rule_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/entities/wallet_entity.dart';
import '../../../domain/repositories/repositories.dart';
import '../../datasources/local/data_change_bus.dart';
import 'vault_data.dart';

/// Sesión de la bóveda: datos en memoria mas la escritura diferida a disco.
///
/// Cada cambio marca la bóveda como sucia y programa un guardado. NO se cifra
/// y se escribe en cada pulsacion: re-serializar y re-cifrar el historial
/// completo por cada letra de una nota sería absurdo. Se agrupan los cambios
/// en una ventana corta y se fuerza el volcado en los momentos que importan
/// (al exportar, al bloquear, al mandar la app a segundo plano).
class VaultSession {
  VaultSession({
    required this.data,
    required this.bus,
    required Future<void> Function() persist,
  }) : _persist = persist;

  final VaultData data;
  final DataChangeBus bus;
  final Future<void> Function() _persist;

  Timer? _debounce;
  Future<void>? _inFlight;

  /// Ventana de agrupación de escrituras.
  ///
  /// Medio segundo es suficiente para fundir la rafaga de cambios de un
  /// formulario y lo bastante corto como para que cerrar la pestana justo
  /// después de guardar un gasto no lo pierda.
  static const Duration _debounceWindow = Duration(milliseconds: 500);

  /// Marca cambio: avisa a la UI y programa la escritura.
  void touch() {
    bus.notify();
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, () {
      unawaited(flush());
    });
  }

  /// Escribe ya lo que haya pendiente.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    // Si ya hay un guardado en curso se espera a que acabe antes de lanzar
    // otro: dos escrituras simultaneas sobre el mismo registro de IndexedDB
    // podrían dejar la versión antigua encima de la nueva.
    final Future<void>? pending = _inFlight;
    if (pending != null) await pending;

    final Future<void> job = _persist();
    _inFlight = job;
    try {
      await job;
    } finally {
      _inFlight = null;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}

// ---------------------------------------------------------------- Carteras

class VaultWalletRepository implements WalletRepository {
  VaultWalletRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<WalletEntity>> getWallets({bool includeArchived = false}) async {
    final List<WalletEntity> list = _d.wallets.values
        .where((WalletEntity w) => includeArchived || !w.isArchived)
        .toList()
      ..sort((WalletEntity a, WalletEntity b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  @override
  Future<List<WalletWithBalance>> getWalletsWithBalance() async {
    final List<WalletEntity> wallets = await getWallets();
    return wallets
        .map((WalletEntity w) => WalletWithBalance(
              wallet: w,
              balanceCents: VaultQueries.walletBalance(_d, w),
            ))
        .toList(growable: false);
  }

  @override
  Future<WalletEntity?> getById(String id) async => _d.wallets[id];

  @override
  Future<WalletEntity?> getDefault() async {
    final List<WalletEntity> list = await getWallets();
    if (list.isEmpty) return null;
    return list.firstWhere(
      (WalletEntity w) => w.isDefault,
      orElse: () => list.first,
    );
  }

  @override
  Future<void> create(WalletEntity wallet) async {
    if (wallet.name.trim().isEmpty) {
      throw const ValidationFailure('La cartera necesita un nombre.');
    }
    if (wallet.isDefault) _clearDefault(wallet.id);
    _d.wallets[wallet.id] = wallet;
    _session.touch();
  }

  @override
  Future<void> update(WalletEntity wallet) async {
    if (wallet.name.trim().isEmpty) {
      throw const ValidationFailure('La cartera necesita un nombre.');
    }
    if (wallet.isDefault) _clearDefault(wallet.id);
    _d.wallets[wallet.id] = wallet;
    _session.touch();
  }

  @override
  Future<void> archive(String id) async {
    final int active =
        _d.wallets.values.where((WalletEntity w) => !w.isArchived).length;
    if (active <= 1) {
      throw const ValidationFailure('Debe quedar al menos una cartera activa.');
    }
    final WalletEntity? w = _d.wallets[id];
    if (w == null) return;
    _d.wallets[id] = w.copyWith(isArchived: true, isDefault: false);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final WalletEntity? w = _d.wallets[id];
    if (w == null) return;
    _d.wallets[id] = w.copyWith(isArchived: false);
    _session.touch();
  }

  @override
  Future<void> deleteForever(String id) async {
    _d.wallets.remove(id);
    // Replica el ON DELETE CASCADE de SQLite: sin esto quedarían movimientos
    // apuntando a una cartera inexistente y los saldos dejarían de cuadrar.
    _d.transactions.removeWhere(
      (_, TransactionEntity t) => t.walletId == id,
    );
    _d.recurring.removeWhere((_, RecurringRuleEntity r) => r.walletId == id);
    _session.touch();
  }

  void _clearDefault(String exceptId) {
    for (final MapEntry<String, WalletEntity> e in _d.wallets.entries.toList()) {
      if (e.key != exceptId && e.value.isDefault) {
        _d.wallets[e.key] = e.value.copyWith(isDefault: false);
      }
    }
  }
}

// -------------------------------------------------------------- Categorías

class VaultCategoryRepository implements CategoryRepository {
  VaultCategoryRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<CategoryEntity>> getCategories({
    TransactionType? type,
    bool includeDeleted = false,
  }) async {
    final List<CategoryEntity> list = _d.categories.values
        .where((CategoryEntity c) =>
            (includeDeleted || !c.isDeleted) && (type == null || c.type == type))
        .toList()
      ..sort((CategoryEntity a, CategoryEntity b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0
            ? byOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  @override
  Future<CategoryEntity?> getById(String id) async => _d.categories[id];

  @override
  Future<void> create(CategoryEntity category) async {
    if (category.name.trim().isEmpty) {
      throw const ValidationFailure('La categoría necesita un nombre.');
    }
    _d.categories[category.id] = category;
    _session.touch();
  }

  @override
  Future<void> update(CategoryEntity category) async {
    if (category.name.trim().isEmpty) {
      throw const ValidationFailure('La categoría necesita un nombre.');
    }
    _d.categories[category.id] = category;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final CategoryEntity? c = _d.categories[id];
    if (c == null) return;
    _d.categories[id] = c.copyWith(isDeleted: true);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final CategoryEntity? c = _d.categories[id];
    if (c == null) return;
    _d.categories[id] = c.copyWith(isDeleted: false);
    _session.touch();
  }

  @override
  Future<int> usageCount(String id) async => _d.transactions.values
      .where((TransactionEntity t) => !t.isDeleted && t.categoryId == id)
      .length;

  @override
  Future<void> reorder(List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      final CategoryEntity? c = _d.categories[orderedIds[i]];
      if (c != null) _d.categories[c.id] = c.copyWith(sortOrder: i);
    }
    _session.touch();
  }
}

// ------------------------------------------------------------ Movimientos

class VaultTransactionRepository implements TransactionRepository {
  VaultTransactionRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<TransactionView>> getRecent({
    int limit = 50,
    int offset = 0,
    String? walletId,
  }) async {
    final List<TransactionEntity> all = VaultQueries.liveTransactions(_d)
        .where((TransactionEntity t) =>
            walletId == null ||
            t.walletId == walletId ||
            t.transferWalletId == walletId)
        .toList()
      ..sort(VaultQueries.byRecency);

    return all
        .skip(offset)
        .take(limit)
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<List<TransactionView>> getInRange(
    DateRange range, {
    String? walletId,
    String? categoryId,
    TransactionType? type,
  }) async {
    final List<TransactionEntity> all = VaultQueries.liveTransactions(_d)
        .where((TransactionEntity t) =>
            range.contains(t.occurredAt) &&
            (walletId == null || t.walletId == walletId) &&
            (categoryId == null || t.categoryId == categoryId) &&
            (type == null || t.type == type))
        .toList()
      ..sort(VaultQueries.byRecency);

    return all
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<List<TransactionView>> search(String term) async {
    final String needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const <TransactionView>[];

    final List<TransactionEntity> all =
        VaultQueries.liveTransactions(_d).where((TransactionEntity t) {
      final String note = (t.note ?? '').toLowerCase();
      final String category =
          (_d.categories[t.categoryId]?.name ?? '').toLowerCase();
      return note.contains(needle) || category.contains(needle);
    }).toList()
          ..sort(VaultQueries.byRecency);

    return all
        .take(100)
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<TransactionView?> getById(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    return t == null ? null : VaultQueries.toView(_d, t);
  }

  @override
  Future<void> create(TransactionEntity tx) async {
    _validate(tx);
    _d.transactions[tx.id] = tx;
    _session.touch();
  }

  @override
  Future<void> update(TransactionEntity tx) async {
    _validate(tx);
    _d.transactions[tx.id] = tx;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    if (t == null) return;
    _d.transactions[id] = t.copyWith(isDeleted: true);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    if (t == null) return;
    _d.transactions[id] = t.copyWith(isDeleted: false);
    _session.touch();
  }

  @override
  Future<int> purgeDeleted({int olderThanDays = 30}) async {
    final DateTime cutoff =
        DateTime.now().subtract(Duration(days: olderThanDays));
    final List<String> doomed = _d.transactions.values
        .where((TransactionEntity t) =>
            t.isDeleted && t.updatedAt.isBefore(cutoff))
        .map((TransactionEntity t) => t.id)
        .toList(growable: false);

    for (final String id in doomed) {
      _d.transactions.remove(id);
    }
    if (doomed.isNotEmpty) _session.touch();
    return doomed.length;
  }

  @override
  Future<DateTime?> earliestDate() async {
    DateTime? earliest;
    for (final TransactionEntity t in VaultQueries.liveTransactions(_d)) {
      if (earliest == null || t.occurredAt.isBefore(earliest)) {
        earliest = t.occurredAt;
      }
    }
    return earliest;
  }

  void _validate(TransactionEntity tx) {
    if (tx.amountCents <= 0) {
      throw const ValidationFailure('El importe debe ser mayor que cero.');
    }
    if (!_d.wallets.containsKey(tx.walletId)) {
      throw const ValidationFailure('La cartera indicada no existe.');
    }
    if (tx.isTransfer) {
      if (tx.transferWalletId == null) {
        throw const ValidationFailure('Elige la cartera de destino.');
      }
      if (tx.transferWalletId == tx.walletId) {
        throw const ValidationFailure(
          'El origen y el destino no pueden ser la misma cartera.',
        );
      }
    }
  }
}

// ----------------------------------------------------------- Presupuestos

class VaultBudgetRepository implements BudgetRepository {
  VaultBudgetRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<BudgetEntity>> getAll() async => _d.budgets.values
      .where((BudgetEntity b) => !b.isDeleted)
      .toList(growable: false);

  @override
  Future<List<BudgetProgress>> getProgressForMonth(DateTime month) async =>
      VaultQueries.budgetProgress(_d, month);

  @override
  Future<BudgetProgress?> getGlobalProgress(DateTime month) async {
    for (final BudgetProgress p in VaultQueries.budgetProgress(_d, month)) {
      if (p.budget.isGlobal) return p;
    }
    return null;
  }

  @override
  Future<void> save(BudgetEntity budget) async {
    if (budget.limitCents <= 0) {
      throw const ValidationFailure('El límite debe ser mayor que cero.');
    }

    // Equivale al índice único parcial de SQLite: como máximo un presupuesto
    // vivo por pareja (categoría, mes).
    final BudgetEntity? duplicate = _d.budgets.values.cast<BudgetEntity?>().firstWhere(
          (BudgetEntity? b) =>
              b != null &&
              !b.isDeleted &&
              b.id != budget.id &&
              b.categoryId == budget.categoryId &&
              b.monthKey == budget.monthKey,
          orElse: () => null,
        );

    if (duplicate != null) {
      _d.budgets[duplicate.id] =
          duplicate.copyWith(limitCents: budget.limitCents);
    } else {
      _d.budgets[budget.id] = budget;
    }
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final BudgetEntity? b = _d.budgets[id];
    if (b == null) return;
    _d.budgets[id] = b.copyWith(isDeleted: true);
    _session.touch();
  }

  @override
  Future<Set<String?>> occupiedCategoryIds(DateTime month) async =>
      VaultQueries.budgetProgress(_d, month)
          .map((BudgetProgress p) => p.budget.categoryId)
          .toSet();
}

// ----------------------------------------------------------- Estadísticas

class VaultAnalyticsRepository implements AnalyticsRepository {
  VaultAnalyticsRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<int> getLifetimeBalance() async => VaultQueries.lifetimeBalance(_d);

  @override
  Future<PeriodTotals> getTotals(DateRange range) async =>
      VaultQueries.totals(_d, range);

  @override
  Future<List<CategorySpending>> getExpenseByCategory(DateRange range) async =>
      VaultQueries.expenseByCategory(_d, range);

  @override
  Future<List<SeriesBucket>> getSeries(
    StatsPeriod period,
    DateTime anchor,
  ) async =>
      VaultQueries.series(_d, period, anchor);

  @override
  Future<int> getAverageDailyExpense(DateTime month) async {
    final DateRange range = DateRange.monthOf(month);
    final PeriodTotals totals = VaultQueries.totals(_d, range);
    final DateTime now = DateTime.now();
    final int elapsed = range.contains(now)
        ? now.day
        : range.end.difference(range.start).inDays;
    return elapsed <= 0 ? 0 : (totals.expenseCents / elapsed).round();
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final DateTime now = DateTime.now();
    final BudgetProgress? global = await VaultBudgetRepository(_session)
        .getGlobalProgress(now);

    return DashboardSummary(
      lifetimeBalanceCents: VaultQueries.lifetimeBalance(_d),
      monthTotals: VaultQueries.totals(_d, DateRange.monthOf(now)),
      currencyCode: _d.settings[AppConstants.kCurrencyCode] ?? 'EUR',
      budgetLimitCents: global?.limitCents,
      budgetSpentCents: global?.spentCents,
    );
  }
}

// --------------------------------------------------------------- Ajustes

class VaultSettingsRepository implements SettingsRepository {
  VaultSettingsRepository(this._session);

  final VaultSession _session;

  @override
  Future<Map<String, String>> getAll() async =>
      Map<String, String>.of(_session.data.settings);

  @override
  Future<String?> get(String key) async => _session.data.settings[key];

  @override
  Future<void> set(String key, String value) async {
    _session.data.settings[key] = value;
    _session.touch();
  }

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final String? raw = _session.data.settings[key];
    if (raw == null) return fallback;
    return raw.toLowerCase() == 'true' || raw == '1';
  }

  @override
  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');
}

// ------------------------------------------------------------ Recurrentes

class VaultRecurringRepository implements RecurringRepository {
  VaultRecurringRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  static const int _maxCatchUpPerRule = 120;

  @override
  Future<List<RecurringRuleEntity>> getAll({bool onlyActive = false}) async {
    final List<RecurringRuleEntity> list = _d.recurring.values
        .where((RecurringRuleEntity r) =>
            !r.isDeleted && (!onlyActive || r.isActive))
        .toList()
      ..sort((RecurringRuleEntity a, RecurringRuleEntity b) =>
          a.nextRunAt.compareTo(b.nextRunAt));
    return list;
  }

  @override
  Future<RecurringRuleEntity?> getById(String id) async => _d.recurring[id];

  @override
  Future<void> create(RecurringRuleEntity rule) async {
    _validate(rule);
    _d.recurring[rule.id] = rule;
    _session.touch();
  }

  @override
  Future<void> update(RecurringRuleEntity rule) async {
    _validate(rule);
    _d.recurring[rule.id] = rule;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final RecurringRuleEntity? r = _d.recurring[id];
    if (r == null) return;
    _d.recurring[id] = r.copyWith(isDeleted: true, isActive: false);
    _session.touch();
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final RecurringRuleEntity? r = _d.recurring[id];
    if (r == null) return;
    _d.recurring[id] = r.copyWith(isActive: active);
    _session.touch();
  }

  @override
  Future<int> materializeDue() async {
    final DateTime now = DateTime.now();
    int created = 0;

    for (final RecurringRuleEntity rule in await getAll(onlyActive: true)) {
      if (rule.nextRunAt.isAfter(now)) continue;

      DateTime cursor = rule.nextRunAt;
      DateTime? lastRun = rule.lastRunAt;
      int guard = 0;

      while (!cursor.isAfter(now) && guard < _maxCatchUpPerRule) {
        final DateTime? end = rule.endAt;
        if (end != null && cursor.isAfter(end)) break;

        final DateTime stamp = DateTime.now();
        final TransactionEntity tx = TransactionEntity(
          id: IdGenerator.newId(),
          walletId: rule.walletId,
          categoryId: rule.categoryId,
          type: rule.type,
          amountCents: rule.amountCents,
          note: rule.note,
          occurredAt: cursor,
          recurringRuleId: rule.id,
          createdAt: stamp,
          updatedAt: stamp,
        );
        _d.transactions[tx.id] = tx;
        created++;

        lastRun = cursor;
        cursor = rule.advanceFrom(cursor);
        guard++;
      }

      final DateTime? end = rule.endAt;
      final bool finished = end != null && cursor.isAfter(end);
      _d.recurring[rule.id] = rule.copyWith(
        nextRunAt: cursor,
        lastRunAt: lastRun,
        isActive: !finished,
      );
    }

    if (created > 0) _session.touch();
    return created;
  }

  void _validate(RecurringRuleEntity rule) {
    if (rule.amountCents <= 0) {
      throw const ValidationFailure('El importe debe ser mayor que cero.');
    }
    if (rule.intervalCount <= 0) {
      throw const ValidationFailure('El intervalo debe ser al menos 1.');
    }
    if (rule.type == TransactionType.transfer) {
      throw const ValidationFailure(
        'Los traspasos no pueden programarse como recurrentes.',
      );
    }
  }
}

// =========================================================================
//  Consultas
// =========================================================================

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

    final DateTime now = DateTime.now();
    final List<TransactionEntity> live = liveTransactions(d).toList(growable: false);

    return starts.map((DateTime start) {
      final DateTime end = _bucketEnd(period, start);
      int income = 0;
      int expense = 0;

      for (final TransactionEntity t in live) {
        if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
          continue;
        }
        switch (t.type) {
          case TransactionType.income:
            income += t.amountCents;
          case TransactionType.expense:
            expense += t.amountCents;
          case TransactionType.transfer:
            break;
        }
      }

      return SeriesBucket(
        label: _bucketLabel(period, start),
        start: start,
        incomeCents: income,
        expenseCents: expense,
        isCurrent: !now.isBefore(start) && now.isBefore(end),
      );
    }).toList(growable: false);
  }

  /// Presupuestos vigentes del mes con su consumo.
  ///
  /// Reproduce la herencia del `NOT EXISTS` de la consulta SQL: para cada
  /// categoría (y para el global) manda el presupuesto puntual del mes y, si no
  /// lo hay, la plantilla que se repite todos los meses.
  static List<BudgetProgress> budgetProgress(VaultData d, DateTime month) {
    final DateRange range = DateRange.monthOf(month);
    final String key = range.monthKey;

    final List<BudgetEntity> live = d.budgets.values
        .where((BudgetEntity b) => !b.isDeleted)
        .toList(growable: false);

    // Primero los puntuales del mes; después las plantillas que no tengan un
    // puntual para su misma categoría.
    final Map<String, BudgetEntity> effective = <String, BudgetEntity>{};
    for (final BudgetEntity b in live) {
      if (b.monthKey == key) {
        effective[b.categoryId ?? '@global'] = b;
      }
    }
    for (final BudgetEntity b in live) {
      if (b.monthKey == null) {
        effective.putIfAbsent(b.categoryId ?? '@global', () => b);
      }
    }

    // Gasto del mes por categoría, calculado una sola vez.
    int globalSpent = 0;
    final Map<String, int> byCategory = <String, int>{};
    for (final TransactionEntity t in liveTransactions(d)) {
      if (t.type != TransactionType.expense) continue;
      if (!range.contains(t.occurredAt)) continue;
      globalSpent += t.amountCents;
      final String? cat = t.categoryId;
      if (cat != null) {
        byCategory[cat] = (byCategory[cat] ?? 0) + t.amountCents;
      }
    }

    final List<BudgetProgress> result = effective.values.map((BudgetEntity b) {
      final CategoryEntity? c =
          b.categoryId == null ? null : d.categories[b.categoryId];
      return BudgetProgress(
        budget: b,
        spentCents:
            b.categoryId == null ? globalSpent : (byCategory[b.categoryId] ?? 0),
        monthKey: key,
        categoryName: c?.name,
        categoryIconCode: c?.iconCode,
        categoryColor: c?.colorValue,
      );
    }).toList()
      ..sort((BudgetProgress a, BudgetProgress b) {
        // El global primero, luego por orden de categoría.
        if (a.budget.isGlobal != b.budget.isGlobal) {
          return a.budget.isGlobal ? -1 : 1;
        }
        final int ao = d.categories[a.budget.categoryId]?.sortOrder ?? 9999;
        final int bo = d.categories[b.budget.categoryId]?.sortOrder ?? 9999;
        return ao.compareTo(bo);
      });

    return result;
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
