import 'package:flutter/material.dart';

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
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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
