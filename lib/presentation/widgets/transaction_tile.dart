import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_range.dart';
import '../../domain/entities/transaction_entity.dart';
import 'common.dart';

/// Fila de un movimiento en la lista del dashboard.
///
/// Se desliza para borrar ([onDelete]) porque es la acción que mas se repite
/// al corregir un apunte mal metido, y abrir un menu para algo tan frecuente
/// sobra.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.view,
    required this.currencyCode,
    this.onTap,
    this.onDelete,
    super.key,
  });

  final TransactionView view;
  final String currencyCode;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TransactionEntity tx = view.transaction;

    final Widget tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: <Widget>[
            IconBadge(
              iconCode: view.categoryIconCode,
              colorValue: view.categoryColor,
              fallbackIcon: tx.isTransfer
                  ? Icons.swap_horiz_rounded
                  : Icons.category_outlined,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    view.displayTitle,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${view.displaySubtitle} · ${AppDates.time(tx.occurredAt)}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AmountText(
              cents: tx.amountCents,
              currencyCode: currencyCode,
              type: tx.type,
            ),
          ],
        ),
      ),
    );

    if (onDelete == null) return tile;

    return Dismissible(
      key: ValueKey<String>('tx-${tx.id}'),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(theme: theme),
      onDismissed: (_) => onDelete!.call(),
      child: tile,
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
    );
  }
}

/// Cabecera de un día dentro de la lista agrupada.
class DayHeader extends StatelessWidget {
  const DayHeader({
    required this.day,
    required this.netCents,
    required this.currencyCode,
    super.key,
  });

  final DateTime day;
  final int netCents;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              AppDates.dayHeader(day),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AmountText(
            cents: netCents,
            currencyCode: currencyCode,
            style: theme.textTheme.labelMedium,
            showSign: false,
          ),
        ],
      ),
    );
  }
}
