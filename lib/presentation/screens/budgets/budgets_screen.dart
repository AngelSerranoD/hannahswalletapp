import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../domain/entities/budget_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../categories/categories_screen.dart';
import 'budget_editor_sheet.dart';
import 'widgets/allocation_header.dart';
import 'widgets/budget_card.dart';

/// Presupuestos del mes: un total y tantos límites de categorías como se
/// quiera.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime month = ref.watch(budgetMonthProvider);
    final AsyncValue<List<BudgetProgress>> progress =
        ref.watch(budgetProgressProvider(month));

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle('Presupuestos'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Categorías',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openBudgetEditor(context, month: month),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo límite'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          _MonthNavigator(range: DateRange.monthOf(month)),
          if (progress.valueOrNull case final List<BudgetProgress> budgets
              when budgets.isNotEmpty)
            AllocationHeader(
              allocation: BudgetAllocation.from(budgets),
              currency: ref.watch(currencyProvider),
              onSetTotal: () => openBudgetEditor(context, month: month),
            ),
          Expanded(child: _BudgetList(month: month, progress: progress)),
        ],
      ),
    );
  }
}

class _BudgetList extends ConsumerWidget {
  const _BudgetList({required this.month, required this.progress});

  final DateTime month;
  final AsyncValue<List<BudgetProgress>> progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (progress) {
      AsyncData<List<BudgetProgress>>(:final List<BudgetProgress> value)
          when value.isEmpty =>
        EmptyState(
          icon: Icons.savings_outlined,
          title: 'Sin presupuestos',
          message: 'Pon un total para el mes y repártelo en límites con las '
              'categorías que quieras. El gato te avisará según te acerques.',
          actionLabel: 'Crear el primero',
          onAction: () => openBudgetEditor(context, month: month),
        ),
      AsyncData<List<BudgetProgress>>(:final List<BudgetProgress> value) =>
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int index) => BudgetCard(
            progress: value[index],
            currency: ref.watch(currencyProvider),
            onEdit: () => openBudgetEditor(
              context,
              month: month,
              existing: value[index],
            ),
            onDelete: () => _confirmDelete(context, ref, value[index]),
          ),
        ),
      AsyncError<List<BudgetProgress>>(:final Object error) => FailureView(
          message: error.toString(),
          onRetry: () => ref.invalidate(budgetProgressProvider(month)),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BudgetProgress progress,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Eliminar límite'),
        content: Text(
          'Se quitará el límite "${progress.displayName}". '
          'Tus movimientos y tus categorías no se tocan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(budgetRepositoryProvider).softDelete(progress.budget.id);
  }
}

/// Navegación entre meses.
class _MonthNavigator extends ConsumerWidget {
  const _MonthNavigator({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: () => _shift(ref, -1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              range.label(StatsPeriod.month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => _shift(ref, 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  void _shift(WidgetRef ref, int delta) {
    ref.read(budgetMonthProvider.notifier).state =
        DateTime(range.start.year, range.start.month + delta);
  }
}
