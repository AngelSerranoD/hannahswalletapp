import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/analytics.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/balance_header.dart';
import '../../widgets/common.dart';
import '../categories/categories_screen.dart';
import '../../widgets/transaction_tile.dart';
import '../transaction/transaction_editor_screen.dart';

/// Pantalla principal.
///
/// Estructura: cabecera fija con el saldo acumulado y la mascota, y debajo la
/// lista de movimientos recientes agrupados por día.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardSummary> summary =
        ref.watch(dashboardSummaryProvider);
    final List<TransactionDayGroup> groups =
        ref.watch(groupedTransactionsProvider);
    final String currency = ref.watch(currencyProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(recentTransactionsProvider);
            await ref.read(dashboardSummaryProvider.future);
          },
          child: CustomScrollView(
            // `always` para que el gesto de recargar funcione también cuando
            // la lista aun no llena la pantalla.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: switch (summary) {
                  AsyncData<DashboardSummary>(:final DashboardSummary value) =>
                    BalanceHeader(summary: value),
                  AsyncError<DashboardSummary>(:final Object error) =>
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: FailureView(
                        message: _messageFor(error),
                        onRetry: () => ref.invalidate(dashboardSummaryProvider),
                      ),
                    ),
                  // Mientras carga por primera vez se reserva la altura de la
                  // cabecera: sin esto, la lista salta hacia abajo al llegar
                  // los datos.
                  _ => const SizedBox(height: 300),
                },
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  // Acceso directo a las categorías desde la pantalla
                  // principal: estaban solo en Ajustes, tres toques adentro,
                  // cuando son de lo que más se retoca al empezar a usar la app.
                  child: SectionHeader(
                    title: 'Movimientos recientes',
                    actionLabel: 'Categorías',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CategoriesScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              if (groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Aún no hay movimientos',
                    message:
                        'Anota tu primer gasto o ingreso con los botones de abajo. '
                        'El gato reacciona a cómo va tu presupuesto.',
                  ),
                )
              else
                ..._buildDaySlivers(context, ref, groups, currency),
              // Hueco para que el último movimiento no quede tapado por los FAB.
              const SliverToBoxAdapter(child: SizedBox(height: 150)),
            ],
          ),
        ),
      ),
      floatingActionButton: const _DualFab(),
    );
  }

  List<Widget> _buildDaySlivers(
    BuildContext context,
    WidgetRef ref,
    List<TransactionDayGroup> groups,
    String currency,
  ) {
    final List<Widget> slivers = <Widget>[];

    for (final TransactionDayGroup group in groups) {
      slivers.add(
        SliverToBoxAdapter(
          child: DayHeader(
            day: group.day,
            netCents: group.netCents,
            currencyCode: currency,
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList.builder(
            itemCount: group.items.length,
            itemBuilder: (BuildContext context, int index) {
              final TransactionView view = group.items[index];
              return TransactionTile(
                view: view,
                currencyCode: currency,
                onTap: () => _openEditor(context, ref, existing: view),
                onDelete: () => _delete(context, ref, view),
              );
            },
          ),
        ),
      );
    }
    return slivers;
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    TransactionView? existing,
  }) async {
    await TransactionEditorScreen.open(
      context,
      initialType: existing?.transaction.type ?? TransactionType.expense,
      existing: existing?.transaction,
    );
  }

  /// Borrado con deshacer.
  ///
  /// El borrado es LOGICO, así que deshacer solo tiene que quitar la marca:
  /// no hay que reconstruir la fila ni sus relaciones, y por eso el snackbar
  /// puede prometer una restauración instantanea.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TransactionView view,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref
        .read(transactionRepositoryProvider)
        .softDelete(view.transaction.id);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Eliminado: ${view.displayTitle}'),
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: AppColors.warning,
            onPressed: () => ref
                .read(transactionRepositoryProvider)
                .restore(view.transaction.id),
          ),
        ),
      );
  }

  static String _messageFor(Object error) =>
      error is Exception ? error.toString() : 'Algo ha fallado al leer tus datos.';
}

/// Los dos botones flotantes extendidos: gasto e ingreso.
///
/// El gasto va abajo y en color de marca porque es la acción que se repite
/// varias veces al día; el ingreso queda encima, mas discreto, porque se anota
/// una o dos veces al mes.
class _DualFab extends ConsumerWidget {
  const _DualFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        FloatingActionButton.extended(
          heroTag: 'fab-income',
          onPressed: () => _open(context, TransactionType.income),
          backgroundColor: scheme.surface,
          foregroundColor: AppColors.income,
          elevation: 0,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            side: BorderSide(color: scheme.outline),
          ),
          icon: const Icon(Icons.south_west_rounded, size: 19),
          label: const Text('Ingreso'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab-expense',
          onPressed: () => _open(context, TransactionType.expense),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.north_east_rounded, size: 20),
          label: const Text('Nuevo gasto'),
        ),
      ],
    );
  }

  void _open(BuildContext context, TransactionType type) {
    TransactionEditorScreen.open(context, initialType: type);
  }
}
