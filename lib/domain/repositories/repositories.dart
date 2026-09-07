import '../../core/utils/date_range.dart';
import '../entities/analytics.dart';
import '../entities/budget_entity.dart';
import '../entities/category_entity.dart';
import '../entities/recurring_rule_entity.dart';
import '../entities/transaction_entity.dart';
import '../entities/wallet_entity.dart';

/// Contratos de acceso a datos.
///
/// La capa de presentacion depende SOLO de estas interfaces, nunca de sqflite
/// ni de los DAO. Gracias a eso los tests de widget pueden inyectar un doble
/// en memoria sin arrastrar SQLCipher, y un día se podría añadir una
/// implementación sincronizada sin tocar una sola pantalla.
///
/// Van juntas en un archivo a proposito: son declaraciones de una decena de
/// lineas cada una y repartirlas en siete ficheros solo añadiría ruido.

abstract interface class WalletRepository {
  Future<List<WalletEntity>> getWallets({bool includeArchived = false});
  Future<List<WalletWithBalance>> getWalletsWithBalance();
  Future<WalletEntity?> getById(String id);
  Future<WalletEntity?> getDefault();
  Future<void> create(WalletEntity wallet);
  Future<void> update(WalletEntity wallet);
  Future<void> archive(String id);
  Future<void> restore(String id);
  Future<void> deleteForever(String id);
}

abstract interface class CategoryRepository {
  Future<List<CategoryEntity>> getCategories({
    TransactionType? type,
    bool includeDeleted = false,
  });
  Future<CategoryEntity?> getById(String id);
  Future<void> create(CategoryEntity category);
  Future<void> update(CategoryEntity category);
  Future<void> softDelete(String id);
  Future<void> restore(String id);
  Future<int> usageCount(String id);
  Future<void> reorder(List<String> orderedIds);
}

abstract interface class TransactionRepository {
  Future<List<TransactionView>> getRecent({
    int limit,
    int offset,
    String? walletId,
  });
  Future<List<TransactionView>> getInRange(
    DateRange range, {
    String? walletId,
    String? categoryId,
    TransactionType? type,
  });
  Future<List<TransactionView>> search(String term);
  Future<TransactionView?> getById(String id);
  Future<void> create(TransactionEntity tx);
  Future<void> update(TransactionEntity tx);
  Future<void> softDelete(String id);
  Future<void> restore(String id);
  Future<int> purgeDeleted({int olderThanDays});
  Future<DateTime?> earliestDate();
}

abstract interface class BudgetRepository {
  Future<List<BudgetEntity>> getAll();
  Future<List<BudgetProgress>> getProgressForMonth(DateTime month);
  Future<BudgetProgress?> getGlobalProgress(DateTime month);
  Future<void> save(BudgetEntity budget);
  Future<void> softDelete(String id);
  Future<Set<String?>> occupiedCategoryIds(DateTime month);
}

abstract interface class AnalyticsRepository {
  /// Saldo acumulado histórico: la cifra grande de la cabecera.
  Future<int> getLifetimeBalance();
  Future<PeriodTotals> getTotals(DateRange range);
  Future<List<CategorySpending>> getExpenseByCategory(DateRange range);
  Future<List<SeriesBucket>> getSeries(StatsPeriod period, DateTime anchor);
  Future<DashboardSummary> getDashboardSummary();
  Future<int> getAverageDailyExpense(DateTime month);
}

abstract interface class SettingsRepository {
  Future<Map<String, String>> getAll();
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<bool> getBool(String key, {bool fallback = false});
  Future<void> setBool(String key, bool value);
}

abstract interface class RecurringRepository {
  Future<List<RecurringRuleEntity>> getAll({bool onlyActive = false});
  Future<RecurringRuleEntity?> getById(String id);
  Future<void> create(RecurringRuleEntity rule);
  Future<void> update(RecurringRuleEntity rule);
  Future<void> softDelete(String id);
  Future<void> setActive(String id, bool active);

  /// Crea los movimientos pendientes de todas las reglas vencidas.
  /// Devuelve cuantos se generaron.
  Future<int> materializeDue();
}
