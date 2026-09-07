import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/recurring_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/wallet_entity.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/dao/analytics_dao.dart';
import '../datasources/local/dao/budget_dao.dart';
import '../datasources/local/dao/category_dao.dart';
import '../datasources/local/dao/recurring_dao.dart';
import '../datasources/local/dao/settings_dao.dart';
import '../datasources/local/dao/transaction_dao.dart';
import '../datasources/local/dao/wallet_dao.dart';
import '../datasources/local/data_change_bus.dart';

/// Implementaciones sobre SQLCipher.
///
/// Cada repositorio hace tres cosas y solo tres:
///   1. valida las reglas de negocio antes de tocar la base,
///   2. delega la consulta en su DAO,
///   3. avisa al [DataChangeBus] cuando ha escrito, para que la UI se refresque.

class WalletRepositoryImpl implements WalletRepository {
  WalletRepositoryImpl(this._dao, this._bus);

  final WalletDao _dao;
  final DataChangeBus _bus;

  @override
  Future<List<WalletEntity>> getWallets({bool includeArchived = false}) =>
      _dao.findAll(includeArchived: includeArchived);

  @override
  Future<List<WalletWithBalance>> getWalletsWithBalance() =>
      _dao.findAllWithBalance();

  @override
  Future<WalletEntity?> getById(String id) => _dao.findById(id);

  @override
  Future<WalletEntity?> getDefault() => _dao.findDefault();

  @override
  Future<void> create(WalletEntity wallet) async {
    _requireName(wallet.name);
    await _dao.insert(wallet);
    _bus.notify();
  }

  @override
  Future<void> update(WalletEntity wallet) async {
    _requireName(wallet.name);
    await _dao.update(wallet);
    _bus.notify();
  }

  @override
  Future<void> archive(String id) async {
    // No dejar al usuario sin ninguna cartera: sin cartera activa el
    // formulario de nuevo movimiento no tendría donde guardar.
    if (await _dao.countActive() <= 1) {
      throw const ValidationFailure(
        'Debe quedar al menos una cartera activa.',
      );
    }
    await _dao.archive(id);
    _bus.notify();
  }

  @override
  Future<void> restore(String id) async {
    await _dao.restore(id);
    _bus.notify();
  }

  @override
  Future<void> deleteForever(String id) async {
    await _dao.deleteForever(id);
    _bus.notify();
  }

  void _requireName(String name) {
    if (name.trim().isEmpty) {
      throw const ValidationFailure('La cartera necesita un nombre.');
    }
  }
}

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._dao, this._bus);

  final CategoryDao _dao;
  final DataChangeBus _bus;

  @override
  Future<List<CategoryEntity>> getCategories({
    TransactionType? type,
    bool includeDeleted = false,
  }) =>
      _dao.findAll(type: type, includeDeleted: includeDeleted);

  @override
  Future<CategoryEntity?> getById(String id) => _dao.findById(id);

  @override
  Future<void> create(CategoryEntity category) async {
    _requireName(category.name);
    await _dao.insert(category);
    _bus.notify();
  }

  @override
  Future<void> update(CategoryEntity category) async {
    _requireName(category.name);
    await _dao.update(category);
    _bus.notify();
  }

  @override
  Future<void> softDelete(String id) async {
    await _dao.softDelete(id);
    _bus.notify();
  }

  @override
  Future<void> restore(String id) async {
    await _dao.restore(id);
    _bus.notify();
  }

  @override
  Future<int> usageCount(String id) => _dao.usageCount(id);

  @override
  Future<void> reorder(List<String> orderedIds) async {
    await _dao.reorder(orderedIds);
    _bus.notify();
  }

  void _requireName(String name) {
    if (name.trim().isEmpty) {
      throw const ValidationFailure('La categoría necesita un nombre.');
    }
  }
}

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._dao, this._bus);

  final TransactionDao _dao;
  final DataChangeBus _bus;

  @override
  Future<List<TransactionView>> getRecent({
    int limit = 50,
    int offset = 0,
    String? walletId,
  }) =>
      _dao.findRecent(limit: limit, offset: offset, walletId: walletId);

  @override
  Future<List<TransactionView>> getInRange(
    DateRange range, {
    String? walletId,
    String? categoryId,
    TransactionType? type,
  }) =>
      _dao.findInRange(
        range,
        walletId: walletId,
        categoryId: categoryId,
        type: type,
      );

  @override
  Future<List<TransactionView>> search(String term) => _dao.search(term);

  @override
  Future<TransactionView?> getById(String id) => _dao.findById(id);

  @override
  Future<void> create(TransactionEntity tx) async {
    _validate(tx);
    await _dao.insert(tx);
    _bus.notify();
  }

  @override
  Future<void> update(TransactionEntity tx) async {
    _validate(tx);
    await _dao.update(tx);
    _bus.notify();
  }

  @override
  Future<void> softDelete(String id) async {
    await _dao.softDelete(id);
    _bus.notify();
  }

  @override
  Future<void> restore(String id) async {
    await _dao.restore(id);
    _bus.notify();
  }

  @override
  Future<int> purgeDeleted({int olderThanDays = 30}) async {
    final int removed = await _dao.purgeDeleted(olderThanDays: olderThanDays);
    if (removed > 0) _bus.notify();
    return removed;
  }

  @override
  Future<DateTime?> earliestDate() => _dao.earliestDate();

  /// Las mismas reglas que los CHECK de la tabla, pero fallando con un mensaje
  /// que se puede ensenar al usuario en vez de un error crudo de SQLite.
  void _validate(TransactionEntity tx) {
    if (tx.amountCents <= 0) {
      throw const ValidationFailure('El importe debe ser mayor que cero.');
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

class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl(this._dao, this._bus);

  final BudgetDao _dao;
  final DataChangeBus _bus;

  @override
  Future<List<BudgetEntity>> getAll() => _dao.findAll();

  @override
  Future<List<BudgetProgress>> getProgressForMonth(DateTime month) =>
      _dao.progressForMonth(month);

  @override
  Future<BudgetProgress?> getGlobalProgress(DateTime month) =>
      _dao.globalProgressForMonth(month);

  @override
  Future<void> save(BudgetEntity budget) async {
    if (budget.limitCents <= 0) {
      throw const ValidationFailure('El límite debe ser mayor que cero.');
    }
    await _dao.upsert(budget);
    _bus.notify();
  }

  @override
  Future<void> softDelete(String id) async {
    await _dao.softDelete(id);
    _bus.notify();
  }

  @override
  Future<Set<String?>> occupiedCategoryIds(DateTime month) =>
      _dao.occupiedCategoryIds(month);
}

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  AnalyticsRepositoryImpl(this._dao, this._budgetDao, this._settingsDao);

  final AnalyticsDao _dao;
  final BudgetDao _budgetDao;
  final SettingsDao _settingsDao;

  @override
  Future<int> getLifetimeBalance() => _dao.lifetimeBalance();

  @override
  Future<PeriodTotals> getTotals(DateRange range) => _dao.totalsForRange(range);

  @override
  Future<List<CategorySpending>> getExpenseByCategory(DateRange range) =>
      _dao.expenseByCategory(range);

  @override
  Future<List<SeriesBucket>> getSeries(StatsPeriod period, DateTime anchor) =>
      _dao.series(period, anchor);

  @override
  Future<int> getAverageDailyExpense(DateTime month) =>
      _dao.averageDailyExpense(month);

  /// Resuelve de una tacada todo lo que pinta la cabecera.
  ///
  /// Las cuatro lecturas van en paralelo con `Future.wait`: son consultas
  /// independientes contra la misma conexion y encadenarlas con `await` una
  /// tras otra multiplicaría por cuatro el tiempo hasta el primer frame.
  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final DateTime now = DateTime.now();
    final DateRange month = DateRange.monthOf(now);

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _dao.lifetimeBalance(),
      _dao.totalsForRange(month),
      _budgetDao.globalProgressForMonth(now),
      _settingsDao.read(AppConstants.kCurrencyCode),
    ]);

    final BudgetProgress? budget = results[2] as BudgetProgress?;

    return DashboardSummary(
      lifetimeBalanceCents: results[0]! as int,
      monthTotals: results[1]! as PeriodTotals,
      currencyCode: (results[3] as String?) ?? 'EUR',
      budgetLimitCents: budget?.limitCents,
      budgetSpentCents: budget?.spentCents,
    );
  }
}

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._dao, this._bus);

  final SettingsDao _dao;
  final DataChangeBus _bus;

  @override
  Future<Map<String, String>> getAll() => _dao.readAll();

  @override
  Future<String?> get(String key) => _dao.read(key);

  @override
  Future<void> set(String key, String value) async {
    await _dao.write(key, value);
    _bus.notify();
  }

  @override
  Future<bool> getBool(String key, {bool fallback = false}) =>
      _dao.readBool(key, fallback: fallback);

  @override
  Future<void> setBool(String key, bool value) async {
    await _dao.writeBool(key, value);
    _bus.notify();
  }
}

class RecurringRepositoryImpl implements RecurringRepository {
  RecurringRepositoryImpl(this._dao, this._transactionDao, this._bus);

  final RecurringDao _dao;
  final TransactionDao _transactionDao;
  final DataChangeBus _bus;

  @override
  Future<List<RecurringRuleEntity>> getAll({bool onlyActive = false}) =>
      _dao.findAll(onlyActive: onlyActive);

  @override
  Future<RecurringRuleEntity?> getById(String id) => _dao.findById(id);

  @override
  Future<void> create(RecurringRuleEntity rule) async {
    _validate(rule);
    await _dao.insert(rule);
    _bus.notify();
  }

  @override
  Future<void> update(RecurringRuleEntity rule) async {
    _validate(rule);
    await _dao.update(rule);
    _bus.notify();
  }

  @override
  Future<void> softDelete(String id) async {
    await _dao.softDelete(id);
    _bus.notify();
  }

  @override
  Future<void> setActive(String id, bool active) async {
    await _dao.setActive(id, active);
    _bus.notify();
  }

  /// Genera los movimientos que las reglas debieron crear mientras la app
  /// estaba cerrada.
  ///
  /// Recorre en bucle porque una regla puede tener VARIAS ejecuciones
  /// pendientes: si el alquiler es mensual y la app lleva tres meses sin
  /// abrirse, deben aparecer los tres recibos, no solo el último. El límite de
  /// [_maxCatchUpPerRule] evita que una regla diaria con `next_run_at` de hace
  /// dos años genere setecientos apuntes de golpe y bloquee el arranque.
  static const int _maxCatchUpPerRule = 120;

  @override
  Future<int> materializeDue() async {
    final DateTime now = DateTime.now();
    final List<RecurringRuleEntity> due = await _dao.findDue(now);
    if (due.isEmpty) return 0;

    int created = 0;

    for (final RecurringRuleEntity rule in due) {
      DateTime cursor = rule.nextRunAt;
      DateTime? lastRun = rule.lastRunAt;
      int guard = 0;

      while (!cursor.isAfter(now) && guard < _maxCatchUpPerRule) {
        final DateTime? end = rule.endAt;
        if (end != null && cursor.isAfter(end)) break;

        final DateTime timestamp = DateTime.now();
        await _transactionDao.insert(
          TransactionEntity(
            id: IdGenerator.newId(),
            walletId: rule.walletId,
            categoryId: rule.categoryId,
            type: rule.type,
            amountCents: rule.amountCents,
            note: rule.note,
            occurredAt: cursor,
            recurringRuleId: rule.id,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
        created++;
        lastRun = cursor;
        cursor = rule.advanceFrom(cursor);
        guard++;
      }

      final DateTime? end = rule.endAt;
      final bool finished = end != null && cursor.isAfter(end);

      await _dao.update(
        rule.copyWith(
          nextRunAt: cursor,
          lastRunAt: lastRun,
          isActive: !finished,
          updatedAt: DateTime.now(),
        ),
      );
    }

    if (created > 0) _bus.notify();
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
