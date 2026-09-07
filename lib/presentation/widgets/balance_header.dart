import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/analytics.dart';
import '../../domain/entities/mascot_state.dart';
import '../providers/app_settings_provider.dart';
import '../providers/data_providers.dart';
import 'common.dart';
import 'mascot/kitty_mascot_widget.dart';

/// Cabecera del dashboard: saldo acumulado, mascota y estado del presupuesto.
///
/// El número grande es el SALDO HISTORICO, no el neto del mes. Esa fue una
/// decision explicita del diseno de datos: un saldo que se pone a cero cada
/// día 1 no dice nada útil y asusta sin motivo.
class BalanceHeader extends ConsumerWidget {
  const BalanceHeader({required this.summary, super.key});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final MascotState mascot = ref.watch(mascotStateProvider);
    final bool mascotEnabled = ref.watch(settingsSnapshotProvider).mascotEnabled;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
      decoration: const BoxDecoration(
        // Rosa sobre rosa, como la cabecera de Flowfy.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.surfaceAlt, AppColors.background],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppTheme.radiusXL),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Saldo acumulado',
                      style: theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // El saldo cuenta hasta su valor en vez de aparecer de
                    // golpe: el ojo sigue el movimiento y localiza la cifra.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: summary.lifetimeBalanceCents.toDouble(),
                      ),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (BuildContext context, double value, _) {
                        return Text(
                          Money.format(
                            value.round(),
                            currencyCode: summary.currencyCode,
                          ),
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: summary.lifetimeBalanceCents < 0
                                ? AppColors.danger
                                : theme.colorScheme.onSurface,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(mascot.mood.headline, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (mascotEnabled)
                KittyMascotWidget(
                  controller: ref.watch(kittyControllerProvider),
                  state: mascot,
                  size: 136,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _MonthStrip(summary: summary),
          if (summary.hasBudget) ...<Widget>[
            const SizedBox(height: 16),
            _BudgetStrip(summary: summary),
          ],
        ],
      ),
    );
  }
}

/// Ingresos y gastos del mes en curso, uno al lado del otro.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // El periodo se dice UNA vez arriba en lugar de repetirlo en cada
        // tarjeta: "Ingresos del mes" no cabe a 390 px de ancho y se cortaba
        // en "Ingresos del m...".
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'Este mes',
            style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 0.8),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _MiniStat(
                icon: Icons.south_west_rounded,
                label: 'Ingresos',
                cents: summary.monthTotals.incomeCents,
                color: AppColors.income,
                currencyCode: summary.currencyCode,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                icon: Icons.north_east_rounded,
                label: 'Gastos',
                cents: summary.monthTotals.expenseCents,
                color: AppColors.primary,
                currencyCode: summary.currencyCode,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.cents,
    required this.color,
    required this.currencyCode,
  });

  final IconData icon;
  final String label;
  final int cents;
  final Color color;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  Money.format(cents, currencyCode: currencyCode),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra del presupuesto global del mes.
class _BudgetStrip extends StatelessWidget {
  const _BudgetStrip({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int limit = summary.budgetLimitCents ?? 0;
    final int spent = summary.budgetSpentCents ?? 0;
    final int remaining = limit - spent;
    final double ratio = summary.budgetRatio;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Presupuesto del mes',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${(ratio * 100).round()} %',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ProgressBar.colorFor(ratio),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(ratio: ratio),
          const SizedBox(height: 10),
          Text(
            remaining >= 0
                ? 'Te quedan ${Money.format(remaining, currencyCode: summary.currencyCode)} de '
                    '${Money.format(limit, currencyCode: summary.currencyCode)}'
                : 'Te has pasado ${Money.format(-remaining, currencyCode: summary.currencyCode)} '
                    'del límite de ${Money.format(limit, currencyCode: summary.currencyCode)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: remaining >= 0 ? null : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
