import '../../../../domain/entities/budget_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../../../../domain/services/budget_planner.dart';
import '../vault_data.dart';
import 'vault_queries.dart';
import 'vault_session.dart';

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
  Future<BudgetProgress?> getGlobalProgress(DateTime month) async =>
      VaultQueries.budgetProgress(_d, month)
          .where((BudgetProgress p) => p.budget.isGlobal)
          .firstOrNull;

  @override
  Future<void> save(BudgetEntity budget) async {
    final BudgetEntity prepared = BudgetPlanner.prepareSave(
      budget,
      existing: _d.budgets.values,
      categories: _d.categories,
    );
    _d.budgets[prepared.id] = prepared;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final BudgetEntity? b = _d.budgets[id];
    if (b == null) return;
    _d.budgets[id] = b.copyWith(isDeleted: true);
    _session.touch();
  }
}
