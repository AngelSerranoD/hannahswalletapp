import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/analytics.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../../domain/entities/category_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../vault_data.dart';
import 'vault_budget_repository.dart';
import 'vault_queries.dart';
import 'vault_session.dart';

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
    final DateTime now = AppClock.now();
    final int elapsed = range.contains(now)
        ? now.day
        : range.end.difference(range.start).inDays;
    return elapsed <= 0 ? 0 : (totals.expenseCents / elapsed).round();
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final DateTime now = AppClock.now();
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
