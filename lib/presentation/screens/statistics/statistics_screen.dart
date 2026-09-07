import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/analytics.dart';
import '../../../domain/entities/category_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Estadísticas con selector de periodo día / semana / mes / año.
///
/// El selector es lo que hace útiles los mismos datos a dos escalas: "cuanto
/// gasto los martes" y "voy peor que el año pasado" son la misma tabla leida
/// con distinta granularidad.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StatsPeriod period = ref.watch(statsPeriodProvider);
    final DateTime anchor = ref.watch(statsAnchorProvider);
    final DateRange range = ref.watch(statsRangeProvider);
    final String currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const AppTitle('Estadísticas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: <Widget>[
          SegmentedButton<StatsPeriod>(
            segments: StatsPeriod.values
                .map((StatsPeriod p) => ButtonSegment<StatsPeriod>(
                      value: p,
                      label: Text(p.label),
                    ))
                .toList(growable: false),
            selected: <StatsPeriod>{period},
            onSelectionChanged: (Set<StatsPeriod> s) =>
                ref.read(statsPeriodProvider.notifier).state = s.first,
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          _PeriodNavigator(period: period, range: range, anchor: anchor),
          const SizedBox(height: 18),
          _TotalsCard(currency: currency),
          const SizedBox(height: 18),
          _SeriesCard(period: period, currency: currency),
          const SizedBox(height: 18),
          _CategoryBreakdown(currency: currency),
        ],
      ),
    );
  }
}

/// Flechas para moverse por los periodos.
class _PeriodNavigator extends ConsumerWidget {
  const _PeriodNavigator({
    required this.period,
    required this.range,
    required this.anchor,
  });

  final StatsPeriod period;
  final DateRange range;
  final DateTime anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    // No se deja avanzar mas alla del periodo actual: no hay datos del futuro
    // y una gráfica vacia solo confunde.
    final bool canGoForward = range.end.isBefore(DateTime.now());

    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          onPressed: () => _shift(ref, -1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            range.label(period),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: canGoForward ? () => _shift(ref, 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  void _shift(WidgetRef ref, int delta) {
    ref.read(statsAnchorProvider.notifier).state =
        range.shift(period, delta).start;
  }
}

/// Ingresos, gastos y ahorro del periodo.
class _TotalsCard extends ConsumerWidget {
  const _TotalsCard({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PeriodTotals> totals = ref.watch(statsTotalsProvider);
    final PeriodTotals value = totals.valueOrNull ?? const PeriodTotals.zero();

    return SoftCard(
      child: Column(
        children: <Widget>[
          LabelValueRow(
            label: 'Ingresos',
            value: Money.format(value.incomeCents, currencyCode: currency),
            valueColor: AppColors.ink,
          ),
          LabelValueRow(
            label: 'Gastos',
            value: Money.format(value.expenseCents, currencyCode: currency),
            valueColor: AppColors.textSecondary,
          ),
          const Divider(height: 20),
          LabelValueRow(
            label: value.netCents >= 0 ? 'Ahorro' : 'Déficit',
            value: Money.format(value.netCents.abs(), currencyCode: currency),
            valueColor:
                value.netCents >= 0 ? AppColors.ink : AppColors.textSecondary,
          ),
          if (value.incomeCents > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Has guardado el ${(value.savingsRate * 100).round()} % de lo '
                'que entró.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Gráfica de barras de la evolucion.
class _SeriesCard extends ConsumerWidget {
  const _SeriesCard({required this.period, required this.currency});

  final StatsPeriod period;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<SeriesBucket> buckets =
        ref.watch(statsSeriesProvider).valueOrNull ?? const <SeriesBucket>[];

    if (buckets.isEmpty) {
      return const SoftCard(
        child: SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // El eje Y se escala al mayor valor visible. Se añade un 15 % de aire para
    // que la barra mas alta no toque el borde superior de la tarjeta.
    final int maxCents = buckets.fold<int>(
      0,
      (int acc, SeriesBucket b) =>
          <int>[acc, b.incomeCents, b.expenseCents].reduce((int a, int c) => a > c ? a : c),
    );
    final double maxY = maxCents == 0 ? 100 : maxCents * 1.15;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Evolución', style: theme.textTheme.titleMedium),
              ),
              const _LegendDot(color: AppColors.ink, label: 'Ingresos'),
              const SizedBox(width: 12),
              const _LegendDot(
                color: AppColors.textTertiary,
                label: 'Gastos',
                filled: false,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (double value) => FlLine(
                    color: theme.colorScheme.outlineVariant,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: maxY / 2,
                      getTitlesWidget: (double value, TitleMeta meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          Money.formatCompact(
                            value.round(),
                            currencyCode: currency,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final int i = value.round();
                        if (i < 0 || i >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        final SeriesBucket b = buckets[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            b.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight:
                                  b.isCurrent ? FontWeight.w700 : FontWeight.w400,
                              color: b.isCurrent
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.ink,
                    getTooltipItem: (
                      BarChartGroupData group,
                      int groupIndex,
                      BarChartRodData rod,
                      int rodIndex,
                    ) {
                      return BarTooltipItem(
                        Money.format(rod.toY.round(), currencyCode: currency),
                        const TextStyle(
                          color: AppColors.paper,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: <BarChartGroupData>[
                  for (int i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 3,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: buckets[i].incomeCents.toDouble(),
                          color: AppColors.ink,
                          width: _barWidth(buckets.length),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: buckets[i].expenseCents.toDouble(),
                          color: AppColors.textTertiary,
                          width: _barWidth(buckets.length),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  /// Las barras se estrechan cuando hay muchos periodos para que los doce
  /// meses del año quepan sin solaparse.
  static double _barWidth(int count) {
    if (count <= 5) return 14;
    if (count <= 8) return 10;
    return 7;
  }
}

/// Punto de la leyenda.
///
/// Ademas del tono, se distingue por RELLENO frente a CONTORNO. Dos grises a
/// 5:1 se diferencian, pero en un punto de nueve pixeles el margen es
/// demasiado estrecho para fiarlo solo al tono.
class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.filled = true,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Donut de gasto por categoría con su lista ordenada.
class _CategoryBreakdown extends ConsumerStatefulWidget {
  const _CategoryBreakdown({required this.currency});

  final String currency;

  @override
  ConsumerState<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends ConsumerState<_CategoryBreakdown> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<CategorySpending> items =
        ref.watch(statsByCategoryProvider).valueOrNull ??
            const <CategorySpending>[];

    if (items.isEmpty) {
      return const SoftCard(
        padding: EdgeInsets.symmetric(vertical: 36, horizontal: 18),
        child: EmptyState(
          icon: Icons.donut_large_outlined,
          title: 'Sin gastos en este periodo',
          message: 'Cuando anotes gastos verás aquí en que se te va el dinero.',
        ),
      );
    }

    final int total =
        items.fold<int>(0, (int acc, CategorySpending c) => acc + c.totalCents);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Reparto por categoría', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 56,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, PieTouchResponse? res) {
                        setState(() {
                          _touchedIndex = res?.touchedSection == null ||
                                  !event.isInterestedForInteractions
                              ? -1
                              : res!.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    sections: <PieChartSectionData>[
                      for (int i = 0; i < items.length; i++)
                        PieChartSectionData(
                          value: items[i].totalCents.toDouble(),
                          color: Color(items[i].colorValue),
                          radius: _touchedIndex == i ? 34 : 26,
                          showTitle: false,
                        ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 260),
                ),
                // El centro del donut muestra el total, o el detalle de la
                // porcion que se este tocando.
                _DonutCenter(
                  items: items,
                  total: total,
                  touchedIndex: _touchedIndex,
                  currency: widget.currency,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...items.map((CategorySpending c) => _CategoryRow(
                spending: c,
                total: total,
                currency: widget.currency,
              )),
        ],
      ),
    );
  }
}

class _DonutCenter extends StatelessWidget {
  const _DonutCenter({
    required this.items,
    required this.total,
    required this.touchedIndex,
    required this.currency,
  });

  final List<CategorySpending> items;
  final int total;
  final int touchedIndex;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasTouch = touchedIndex >= 0 && touchedIndex < items.length;
    final CategorySpending? touched = hasTouch ? items[touchedIndex] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          touched?.categoryName ?? 'Total',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          Money.format(touched?.totalCents ?? total, currencyCode: currency),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.spending,
    required this.total,
    required this.currency,
  });

  final CategorySpending spending;
  final int total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double share = total == 0 ? 0 : spending.totalCents / total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          IconBadge(
            iconCode: spending.iconCode,
            colorValue: spending.colorValue,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        spending.categoryName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      Money.format(spending.totalCents, currencyCode: currency),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(spending.colorValue),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(share * 100).round()} % · ${spending.entryCount} '
                  '${spending.entryCount == 1 ? 'movimiento' : 'movimientos'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
