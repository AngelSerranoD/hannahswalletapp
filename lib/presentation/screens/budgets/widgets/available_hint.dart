import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../domain/entities/budget_entity.dart';

/// Cuánto quedará libre del total del mes si se guarda el importe escrito.
///
/// Va debajo del campo del importe y se actualiza tecleando, que es donde la
/// cuenta sirve: decidir el número, no descubrir después de guardar que el
/// reparto ya no cabe.
class AvailableHint extends StatelessWidget {
  const AvailableHint({
    required this.allocation,
    required this.currency,
    required this.existing,
    required this.forCategories,
    required this.typedCents,
    super.key,
  });

  final BudgetAllocation allocation;
  final String currency;
  final BudgetEntity? existing;
  final bool forCategories;
  final int typedCents;

  String _money(int cents) => Money.format(cents, currencyCode: currency);

  @override
  Widget build(BuildContext context) {
    if (!forCategories) return _forTotal();

    if (!allocation.hasGlobalBudget) {
      return const _HintLine(
        icon: Icons.info_outline_rounded,
        danger: false,
        text: 'Sin un total del mes no hay de dónde descontar este límite.',
      );
    }

    final int available = allocation.availableForEditing(existing);
    final int rest = available - typedCents;
    return _HintLine(
      icon: Icons.savings_outlined,
      danger: rest < 0,
      text: rest < 0
          ? 'Libre: ${_money(available)}. Con este límite te pasarías '
              '${_money(-rest)} del total.'
          : 'Libre: ${_money(available)}. Con este límite quedarían '
              '${_money(rest)}.',
    );
  }

  /// Editando el total: lo repartido no cambia, cambia la bolsa.
  Widget _forTotal() {
    final int rest = typedCents - allocation.assignedCents;
    final String assigned = _money(allocation.assignedCents);
    return _HintLine(
      icon: Icons.account_balance_wallet_outlined,
      danger: rest < 0,
      text: allocation.limitCount == 0
          ? 'Es el dinero total del mes; los límites de categorías se '
              'repartirán dentro de él.'
          : rest < 0
              ? 'Tus límites ya reparten $assigned: te faltarían '
                  '${_money(-rest)}.'
              : 'Quitando lo repartido en límites ($assigned), quedarían '
                  '${_money(rest)} libres.',
    );
  }
}

class _HintLine extends StatelessWidget {
  const _HintLine({
    required this.icon,
    required this.danger,
    required this.text,
  });

  final IconData icon;
  final bool danger;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppColors.danger : AppColors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
