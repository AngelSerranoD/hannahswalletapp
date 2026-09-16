import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/cjk_font_loader.dart';
import '../../core/utils/date_range.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/wallet_entity.dart';

import 'budgets/budgets_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'settings/settings_screen.dart';
import 'statistics/statistics_screen.dart';

/// Contenedor con la barra de navegación inferior.
///
/// ### Dos decisiones de rendimiento
///
/// **1. Las pestañas se construyen la primera vez que se visitan.** Un
/// `IndexedStack` con las cuatro pantallas de golpe parece inofensivo, pero
/// cada una lanza sus consultas a la bóveda nada más montarse: abrir la app
/// disparaba el dashboard, las estadísticas, los presupuestos y los ajustes a
/// la vez, cuando solo se ve la primera. Aquí se montan bajo demanda y a
/// partir de ahí se conservan, así que el scroll y el periodo elegido siguen
/// donde estaban al volver.
///
/// **2. Solo la pestaña visible tiene los tickers activos.** Es lo que arregla
/// el consumo de verdad: la mascota anima en bucle, y con un `IndexedStack`
/// normal seguía repintándose sesenta veces por segundo mientras el usuario
/// estaba en Ajustes mirando otra cosa. [TickerMode] desconecta las
/// animaciones de lo que no se ve sin destruir su estado.
///
/// Además, al montarse —que es cuando la bóveda ya está abierta— decide si
/// hace falta la fuente china mirando los textos guardados.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Con margen tras el primer frame, para no competir con las consultas de
    // la pantalla que se está abriendo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(Future<void>.delayed(
        const Duration(seconds: 2),
        _loadCjkFontIfDataNeedsIt,
      ));
    });
  }

  /// Carga la fuente china solo si algún nombre o nota guardada la necesita.
  ///
  /// Se recorren todos los movimientos, no los recientes: una nota en chino
  /// de hace un año también tiene que verse bien al buscarla.
  Future<void> _loadCjkFontIfDataNeedsIt() async {
    if (!mounted || CjkFontLoader.isLoaded) return;
    try {
      final DateTime? earliest =
          await ref.read(transactionRepositoryProvider).earliestDate();
      if (!mounted) return;
      final (
        List<CategoryEntity> categories,
        List<WalletEntity> wallets,
        List<TransactionView> movements,
      ) = await (
        ref.read(categoryRepositoryProvider).getCategories(includeDeleted: true),
        ref.read(walletRepositoryProvider).getWallets(includeArchived: true),
        earliest == null
            ? Future<List<TransactionView>>.value(const <TransactionView>[])
            : ref.read(transactionRepositoryProvider).getInRange(DateRange(
                  earliest,
                  DateTime.now().add(const Duration(days: 3660)),
                )),
      ).wait;

      await CjkFontLoader.ensureLoadedFor(<String?>[
        for (final CategoryEntity c in categories) c.name,
        for (final WalletEntity w in wallets) w.name,
        for (final TransactionView t in movements) t.transaction.note,
      ]);
    } catch (error) {
      // Si la bóveda se cierra a medias, no pasa nada: al teclear chino la
      // fuente se pide igualmente.
      debugPrint('No se pudo revisar si hace falta la fuente china: $error');
    }
  }

  int _index = 0;

  /// Pestañas ya visitadas. La primera empieza montada.
  final Set<int> _visited = <int>{0};

  static const int _count = 4;

  Widget _screenAt(int i) => switch (i) {
        0 => const DashboardScreen(),
        1 => const StatisticsScreen(),
        2 => const BudgetsScreen(),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          for (int i = 0; i < _count; i++)
            TickerMode(
              enabled: i == _index,
              // `SizedBox.shrink` como marcador de lo aún no visitado: ocupa
              // cero y no construye nada.
              child: _visited.contains(i)
                  ? _screenAt(i)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Análisis',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings_rounded),
            label: 'Límites',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
