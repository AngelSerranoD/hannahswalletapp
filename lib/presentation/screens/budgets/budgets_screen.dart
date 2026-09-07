import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/budget_entity.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Presupuestos del mes: uno global y tantos por categoría como se quiera.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime month = ref.watch(budgetMonthProvider);
    final AsyncValue<List<BudgetProgress>> progress =
        ref.watch(budgetProgressProvider(month));
    final String currency = ref.watch(currencyProvider);
    final DateRange range = DateRange.monthOf(month);

    return Scaffold(
      appBar: AppBar(title: const AppTitle('Presupuestos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, month: month),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo límite'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          _MonthNavigator(range: range),
          if (progress.valueOrNull case final List<BudgetProgress> budgets
              when budgets.isNotEmpty)
            _AllocationHeader(
              allocation: BudgetAllocation.from(budgets),
              currency: currency,
              onSetTotal: () => _openEditor(context, ref, month: month),
            ),
          Expanded(
            child: switch (progress) {
              AsyncData<List<BudgetProgress>>(:final List<BudgetProgress> value)
                  when value.isEmpty =>
                EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'Sin presupuestos',
                  message:
                      'Pon un límite mensual y el gato te avisará según te acerques. '
                      'Puedes crear uno global y otros por categoría.',
                  actionLabel: 'Crear el primero',
                  onAction: () => _openEditor(context, ref, month: month),
                ),
              AsyncData<List<BudgetProgress>>(:final List<BudgetProgress> value) =>
                ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) => _BudgetCard(
                    progress: value[index],
                    currency: currency,
                    onEdit: () => _openEditor(
                      context,
                      ref,
                      month: month,
                      existing: value[index].budget,
                    ),
                    onDelete: () => _confirmDelete(context, ref, value[index]),
                  ),
                ),
              AsyncError<List<BudgetProgress>>(:final Object error) =>
                FailureView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(budgetProgressProvider(month)),
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required DateTime month,
    BudgetEntity? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BudgetEditorSheet(month: month, existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BudgetProgress progress,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Eliminar presupuesto'),
        content: Text(
          'Se quitará el límite de "${progress.displayName}". '
          'Tus movimientos no se tocan.',
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

/// Cabecera con el dinero total del mes y lo que queda libre para repartir.
///
/// El límite global es la bolsa del mes; cada límite por categoría saca una
/// parte de ella. Sin este resumen había que sumar las tarjetas a mano para
/// saber si todavía cabía otra categoría, que es justo la pregunta que se hace
/// al pulsar "Nuevo límite".
class _AllocationHeader extends StatelessWidget {
  const _AllocationHeader({
    required this.allocation,
    required this.currency,
    required this.onSetTotal,
  });

  final BudgetAllocation allocation;
  final String currency;
  final VoidCallback onSetTotal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!allocation.hasGlobalBudget) {
      return _Frame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.savings_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aún no has puesto el total del mes',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Las categorías reparten ya '
              '${Money.format(allocation.assignedCents, currencyCode: currency)}. '
              'Pon un límite de "Todo el mes" y verás cuánto te queda libre '
              'cada vez que añadas una.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSetTotal,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Poner el total'),
              ),
            ),
          ],
        ),
      );
    }

    final bool over = allocation.isOverAllocated;
    final int available = allocation.availableCents;

    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            over ? 'Te has pasado del total' : 'Libre para nuevas categorías',
            style: theme.textTheme.labelLarge?.copyWith(
              color: over ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  Money.format(
                    over ? -available : available,
                    currencyCode: currency,
                  ),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: over ? AppColors.danger : null,
                  ),
                ),
              ),
              Text(
                'de ${Money.format(allocation.totalCents, currencyCode: currency)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(ratio: allocation.ratio),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _detail(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? AppColors.danger : null,
                  ),
                ),
              ),
              Text(
                '${allocation.percent} %',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ProgressBar.colorFor(allocation.ratio),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _detail() {
    final String assigned =
        Money.format(allocation.assignedCents, currencyCode: currency);
    if (allocation.categoryCount == 0) {
      return 'Todavía no has repartido nada por categorías.';
    }
    final String categories = allocation.categoryCount == 1
        ? '1 categoría'
        : '${allocation.categoryCount} categorías';
    return 'Repartido en $categories: $assigned';
  }
}

/// Marco común de la cabecera: tarjeta destacada sobre la lista.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: SoftCard(color: AppColors.surfaceAlt, child: child),
    );
  }
}

/// Tarjeta de un presupuesto con su barra de consumo.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.progress,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool over = progress.isOverspent;

    return SoftCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                iconCode: progress.categoryIconCode,
                colorValue: progress.categoryColor,
                fallbackIcon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      progress.displayName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      progress.budget.isRecurringTemplate
                          ? 'Se repite cada mes'
                          : 'Solo este mes',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Eliminar',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  Money.format(progress.spentCents, currencyCode: currency),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: over ? AppColors.danger : null,
                  ),
                ),
              ),
              Text(
                'de ${Money.format(progress.limitCents, currencyCode: currency)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(ratio: progress.ratio),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  over
                      ? 'Te has pasado ${Money.format(-progress.remainingCents, currencyCode: currency)}'
                      : 'Quedan ${Money.format(progress.remainingCents, currencyCode: currency)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? AppColors.danger : null,
                  ),
                ),
              ),
              Text(
                '${progress.percent} %',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ProgressBar.colorFor(progress.ratio),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cuánto quedará libre del total del mes si se guarda el importe escrito.
///
/// Va debajo del campo del importe y se actualiza tecleando, que es donde la
/// cuenta sirve: decidir el número, no descubrir después de guardar que el
/// reparto ya no cabe.
class _AvailableHint extends StatelessWidget {
  const _AvailableHint({
    required this.allocation,
    required this.currency,
    required this.existing,
    required this.forCategory,
    required this.typedCents,
  });

  final BudgetAllocation allocation;
  final String currency;
  final BudgetEntity? existing;
  final bool forCategory;
  final int typedCents;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!forCategory) {
      // Editando el total: lo repartido no cambia, cambia la bolsa.
      final int rest = typedCents - allocation.assignedCents;
      final bool short = rest < 0;
      return _line(
        theme,
        icon: Icons.account_balance_wallet_outlined,
        danger: short,
        text: allocation.categoryCount == 0
            ? 'Es el dinero total del mes; las categorías se repartirán dentro de él.'
            : short
                ? 'Tus categorías ya reparten '
                    '${Money.format(allocation.assignedCents, currencyCode: currency)}: '
                    'te faltarían ${Money.format(-rest, currencyCode: currency)}.'
                : 'Quitando lo repartido en categorías '
                    '(${Money.format(allocation.assignedCents, currencyCode: currency)}), '
                    'quedarían ${Money.format(rest, currencyCode: currency)} libres.',
      );
    }

    if (!allocation.hasGlobalBudget) {
      return _line(
        theme,
        icon: Icons.info_outline_rounded,
        danger: false,
        text: 'Sin un límite de "Todo el mes" no hay total del que descontar '
            'este límite.',
      );
    }

    final int available = allocation.availableForEditing(existing);
    final int rest = available - typedCents;
    final bool over = rest < 0;

    return _line(
      theme,
      icon: Icons.savings_outlined,
      danger: over,
      text: over
          ? 'Libre: ${Money.format(available, currencyCode: currency)}. '
              'Con este límite te pasarías '
              '${Money.format(-rest, currencyCode: currency)} del total.'
          : 'Libre: ${Money.format(available, currencyCode: currency)}. '
              'Con este límite quedarían '
              '${Money.format(rest, currencyCode: currency)}.',
    );
  }

  Widget _line(
    ThemeData theme, {
    required IconData icon,
    required bool danger,
    required String text,
  }) {
    final Color color = danger ? AppColors.danger : AppColors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Hoja para crear o editar un presupuesto.
class BudgetEditorSheet extends ConsumerStatefulWidget {
  const BudgetEditorSheet({required this.month, this.existing, super.key});

  final DateTime month;
  final BudgetEntity? existing;

  @override
  ConsumerState<BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<BudgetEditorSheet> {
  late final TextEditingController _limit;
  String? _categoryId;
  late bool _repeatEveryMonth;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final BudgetEntity? existing = widget.existing;
    _limit = TextEditingController(
      text: existing == null ? '' : Money.centsToPlainString(existing.limitCents),
    );
    _categoryId = existing?.categoryId;
    _repeatEveryMonth = existing?.isRecurringTemplate ?? true;
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String currency = ref.watch(currencyProvider);
    final List<CategoryEntity> categories =
        ref.watch(categoriesProvider(TransactionType.expense)).valueOrNull ??
            const <CategoryEntity>[];
    final BudgetAllocation allocation = BudgetAllocation.from(
      ref.watch(budgetProgressProvider(widget.month)).valueOrNull ??
          const <BudgetProgress>[],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        // Deja sitio al teclado: sin esto el campo del importe queda tapado.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.existing == null ? 'Nuevo límite' : 'Editar límite',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _limit,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Límite mensual',
                prefixIcon: const Icon(Icons.euro_rounded),
                suffixText: Money.symbolFor(currency),
              ),
            ),
            const SizedBox(height: 10),
            // Se reconstruye con cada tecla: el objetivo es ver bajar el
            // disponible mientras se escribe, no al guardar.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _limit,
              builder: (BuildContext context, TextEditingValue value, _) =>
                  _AvailableHint(
                allocation: allocation,
                currency: currency,
                existing: widget.existing,
                forCategory: _categoryId != null,
                typedCents: Money.parseToCents(value.text) ?? 0,
              ),
            ),
            const SizedBox(height: 16),
            Text('Se aplica a', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                  avatar: const Icon(Icons.all_inclusive_rounded, size: 18),
                  label: const Text('Todo el mes'),
                ),
                ...categories.map((CategoryEntity c) => ChoiceChip(
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                      avatar: IconBadge(
                        iconCode: c.iconCode,
                        colorValue: c.colorValue,
                        size: 22,
                      ),
                      label: Text(c.name),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _repeatEveryMonth,
              onChanged: (bool v) => setState(() => _repeatEveryMonth = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Repetir cada mes'),
              subtitle: Text(
                _repeatEveryMonth
                    ? 'Vale para todos los meses que no tengan uno propio.'
                    : 'Solo para ${DateRange.monthOf(widget.month).label(StatsPeriod.month).toLowerCase()}.',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final int? cents = Money.parseToCents(_limit.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Escribe un límite mayor que cero.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final DateTime now = DateTime.now();
    final BudgetEntity budget = BudgetEntity(
      id: widget.existing?.id ?? IdGenerator.newId(),
      categoryId: _categoryId,
      monthKey:
          _repeatEveryMonth ? null : DateRange.monthKeyOf(widget.month),
      limitCents: cents,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await ref.read(budgetRepositoryProvider).save(budget);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
