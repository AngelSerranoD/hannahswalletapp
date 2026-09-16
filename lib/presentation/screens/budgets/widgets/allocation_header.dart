import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../widgets/common.dart';

/// Cabecera con el dinero total del mes y lo que queda libre para repartir.
///
/// El límite global es la bolsa del mes; cada límite de categorías saca una
/// parte de ella. Sin este resumen había que sumar las tarjetas a mano para
/// saber si todavía cabía otro límite, que es justo la pregunta que se hace al
/// pulsar "Nuevo límite".
class AllocationHeader extends StatelessWidget {
  const AllocationHeader({
    required this.allocation,
    required this.currency,
    required this.onSetTotal,
    super.key,
  });

  final BudgetAllocation allocation;
  final String currency;
  final VoidCallback onSetTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: SoftCard(
        color: AppColors.surfaceAlt,
        child: allocation.hasGlobalBudget
            ? _Allocation(allocation: allocation, currency: currency)
            : _MissingTotal(
                assignedCents: allocation.assignedCents,
                currency: currency,
                onSetTotal: onSetTotal,
              ),
      ),
    );
  }
}

class _Allocation extends StatelessWidget {
  const _Allocation({required this.allocation, required this.currency});

  final BudgetAllocation allocation;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool over = allocation.isOverAllocated;
    final Color? alert = over ? AppColors.danger : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          over ? 'Te has pasado del total' : 'Libre para nuevos límites',
          style: theme.textTheme.labelLarge
              ?.copyWith(color: alert ?? AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                Money.format(
                  allocation.availableCents.abs(),
                  currencyCode: currency,
                ),
                style: theme.textTheme.headlineSmall?.copyWith(color: alert),
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
                style: theme.textTheme.bodySmall?.copyWith(color: alert),
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
    );
  }

  String _detail() {
    final int n = allocation.limitCount;
    if (n == 0) return 'Todavía no has repartido nada en límites.';
    final String assigned =
        Money.format(allocation.assignedCents, currencyCode: currency);
    return 'Repartido en ${n == 1 ? '1 límite' : '$n límites'}: $assigned';
  }
}

class _MissingTotal extends StatelessWidget {
  const _MissingTotal({
    required this.assignedCents,
    required this.currency,
    required this.onSetTotal,
  });

  final int assignedCents;
  final String currency;
  final VoidCallback onSetTotal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
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
          'Tus límites reparten ya '
          '${Money.format(assignedCents, currencyCode: currency)}. '
          'Pon un total del mes y verás cuánto te queda libre cada vez que '
          'añadas uno.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onSetTotal,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Poner el total'),
        ),
      ],
    );
  }
}
