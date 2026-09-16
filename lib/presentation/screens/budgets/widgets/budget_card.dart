import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../widgets/common.dart';

/// Tarjeta de un presupuesto con su barra de consumo.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    required this.progress,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final BudgetProgress progress;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Title(progress: progress, onDelete: onDelete),
          const SizedBox(height: 14),
          _Amounts(progress: progress, currency: currency),
          const SizedBox(height: 10),
          ProgressBar(ratio: progress.ratio),
          const SizedBox(height: 8),
          _Remaining(progress: progress, currency: currency),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.progress, required this.onDelete});

  final BudgetProgress progress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        IconBadge(
          iconCode: progress.iconCode,
          colorValue: progress.colorValue,
          // Con varias categorías ningún icono las representa a todas.
          fallbackIcon: progress.budget.isGlobal
              ? Icons.account_balance_wallet_outlined
              : Icons.folder_outlined,
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
                _subtitle(),
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
    );
  }

  /// Vigencia y, si el título es un nombre propio, las categorías que cubre:
  /// "Ocio" no dice por sí solo qué gastos cuentan.
  String _subtitle() {
    final String repeat = progress.budget.isRecurringTemplate
        ? 'Se repite cada mes'
        : 'Solo este mes';
    final bool titledByName = progress.displayName != progress.categoryNames;
    return titledByName && progress.categories.isNotEmpty
        ? '${progress.categoryNames} · $repeat'
        : repeat;
  }
}

class _Amounts extends StatelessWidget {
  const _Amounts({required this.progress, required this.currency});

  final BudgetProgress progress;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Text(
            Money.format(progress.spentCents, currencyCode: currency),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: progress.isOverspent ? AppColors.danger : null,
            ),
          ),
        ),
        Text(
          'de ${Money.format(progress.limitCents, currencyCode: currency)}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Remaining extends StatelessWidget {
  const _Remaining({required this.progress, required this.currency});

  final BudgetProgress progress;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool over = progress.isOverspent;
    final String amount =
        Money.format(progress.remainingCents.abs(), currencyCode: currency);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            over ? 'Te has pasado $amount' : 'Quedan $amount',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: over ? AppColors.danger : null),
          ),
        ),
        Text(
          '${progress.percent} %',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: ProgressBar.colorFor(progress.ratio)),
        ),
      ],
    );
  }
}
