import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/di/providers.dart';
import 'package:hannahswalletapp/core/theme/app_theme.dart';
import 'package:hannahswalletapp/core/utils/id_generator.dart';
import 'package:hannahswalletapp/data/backend/app_backend.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/domain/entities/budget_entity.dart';
import 'package:hannahswalletapp/domain/entities/category_entity.dart';
import 'package:hannahswalletapp/domain/entities/transaction_entity.dart';
import 'package:hannahswalletapp/domain/entities/wallet_entity.dart';
import 'package:hannahswalletapp/presentation/providers/bootstrap_provider.dart';
import 'package:hannahswalletapp/presentation/screens/budgets/budgets_screen.dart';
import 'package:hannahswalletapp/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:hannahswalletapp/presentation/screens/lock/vault_gate_screen.dart';
import 'package:hannahswalletapp/presentation/screens/settings/settings_screen.dart';
import 'package:hannahswalletapp/presentation/screens/statistics/statistics_screen.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Capturas de referencia de la interfaz.
///
/// Sirven para dos cosas:
///
///  1. Ver como queda la app sin necesidad de un dispositivo, revisando los
///     PNG de `test/goldens/`.
///  2. Detectar regresiones visuales: si un cambio de tema mueve algo de
///     sitio, estas pruebas fallan y ensenan exactamente que pixel cambio.
///
/// Se regeneran con:
///     flutter test --update-goldens test/goldens_test.dart
void main() {
  // Tamano de un iPhone 13/14 en pixeles logicos: es el objetivo real de la
  // PWA, asi que las capturas se toman con esa forma.
  const Size iPhone = Size(390, 844);

  late final AppBackend backend;

  // La boveda se prepara UNA vez para todas las capturas, y aqui, en
  // `setUpAll`, no dentro de los tests. Dos motivos:
  //
  //  * `testWidgets` corre con un reloj falso: la E/S asincrona del almacen y
  //    las 310 000 iteraciones del KDF se quedarian esperando temporizadores
  //    que nadie avanza, y la prueba se colgaria sin dar error.
  //  * derivar la clave seis veces (una por captura) multiplicaria por seis un
  //    trabajo deliberadamente costoso.
  //
  // Ninguna captura modifica datos, asi que compartir la boveda es seguro.
  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    await _loadRealFonts();
    backend = await _seededBackend();
  });

  Future<void> render(
    WidgetTester tester,
    Widget screen, {
    required AppBackend backend,
    Size size = iPhone,
  }) async {
    tester.view
      ..physicalSize = Size(size.width * 3, size.height * 3)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // `flutter_test` usa por defecto una fuente que dibuja rectangulos negros.
    //
    // Las familias de la app ya vienen del tema; lo que hay que repasar son
    // las copias que `AppTheme` hace de algunos estilos (titulo de la barra,
    // boton flotante, snackbar), porque conservan la fuente que tenian al
    // copiarse y saldrian como cajas negras.
    final ThemeData base = AppTheme.light();

    TextStyle? roboto(TextStyle? style) =>
        style?.copyWith(fontFamily: style.fontFamily ?? AppTheme.bodyFont);

    final ThemeData themed = base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: roboto(base.appBarTheme.titleTextStyle),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        extendedTextStyle: roboto(
          base.floatingActionButtonTheme.extendedTextStyle,
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: roboto(base.snackBarTheme.contentTextStyle),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            roboto(base.textTheme.labelLarge),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBackendProvider.overrideWithValue(backend),
          // El arranque ya esta hecho por `_seededBackend`, asi que se
          // cortocircuita para que la pantalla salga directamente.
          appBootstrapProvider.overrideWith(
            (Ref ref) async => const BootstrapResult(status: BackendStatus.ready),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themed,
          locale: const Locale('es', 'ES'),
          supportedLocales: const <Locale>[Locale('es', 'ES')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: screen,
        ),
      ),
    );

    // `pumpAndSettle` NO sirve aqui: la mascota tiene una animacion en bucle
    // que nunca termina, asi que esperaria para siempre. Se avanza un tiempo
    // fijo, suficiente para que carguen los datos y se asienten las
    // transiciones de entrada.
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('dashboard en claro', (WidgetTester tester) async {
    await render(tester, const DashboardScreen(), backend: backend);
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard_claro.png'),
    );
  });

  testWidgets('estadisticas', (WidgetTester tester) async {
    await render(tester, const StatisticsScreen(), backend: backend);
    await expectLater(
      find.byType(StatisticsScreen),
      matchesGoldenFile('goldens/estadisticas.png'),
    );
  });

  testWidgets('presupuestos', (WidgetTester tester) async {
    await render(tester, const BudgetsScreen(), backend: backend);
    await expectLater(
      find.byType(BudgetsScreen),
      matchesGoldenFile('goldens/presupuestos.png'),
    );
  });

  testWidgets('ajustes', (WidgetTester tester) async {
    await render(tester, const SettingsScreen(), backend: backend);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/ajustes.png'),
    );
  });

  testWidgets('creacion de la boveda', (WidgetTester tester) async {
    await render(
      tester,
      const VaultGateScreen(mode: BackendStatus.needsSetup),
      backend: backend,
    );
    await expectLater(
      find.byType(VaultGateScreen),
      matchesGoldenFile('goldens/boveda_crear.png'),
    );
  });
}

/// Prepara una boveda en memoria con datos de ejemplo deterministas.
Future<AppBackend> _seededBackend() async {
  final WebBackend backend =
      WebBackend(store: VaultStore(factory: idbFactoryMemory));
  await backend.initialize();
  await backend.create(passphrase: 'contrasena-de-prueba');

  final List<WalletEntity> wallets = await backend.wallets.getWallets();
  final String walletId = wallets.first.id;
  final List<CategoryEntity> expenses =
      await backend.categories.getCategories(type: TransactionType.expense);
  final List<CategoryEntity> incomes =
      await backend.categories.getCategories(type: TransactionType.income);

  // Fechas RELATIVAS a hoy, con la hora fija.
  //
  // Con fechas absolutas las capturas cambiaban solas: la cabecera del
  // dashboard dice "Hoy" o "Ayer" comparando con la fecha real, asi que una
  // captura generada el dia 20 empezaba a fallar el 21. Anclando los datos a
  // `DateTime.now()` y fijando solo la hora, el texto es siempre el mismo y la
  // prueba deja de caducar.
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 18, 30);
  DateTime daysAgo(int days, int hour, [int minute = 0]) {
    final DateTime d = today.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  Future<void> add({
    required TransactionType type,
    required int cents,
    required String categoryId,
    required String note,
    required DateTime when,
  }) {
    return backend.transactions.create(TransactionEntity(
      id: IdGenerator.newId(),
      walletId: walletId,
      categoryId: categoryId,
      type: type,
      amountCents: cents,
      note: note,
      occurredAt: when,
      createdAt: when,
      updatedAt: when,
    ));
  }

  await add(
    type: TransactionType.income,
    cents: 195000,
    categoryId: incomes.first.id,
    note: 'Nomina de agosto',
    when: daysAgo(19, 9),
  );
  await add(
    type: TransactionType.expense,
    cents: 4290,
    categoryId: expenses[0].id,
    note: 'Compra semanal',
    when: today,
  );
  await add(
    type: TransactionType.expense,
    cents: 1850,
    categoryId: expenses[1].id,
    note: 'Cena con Marta',
    when: daysAgo(0, 14, 15),
  );
  await add(
    type: TransactionType.expense,
    cents: 6500,
    categoryId: expenses[3].id,
    note: 'Luz y agua',
    when: daysAgo(1, 11),
  );
  await add(
    type: TransactionType.expense,
    cents: 1290,
    categoryId: expenses[8].id,
    note: 'Suscripcion musica',
    when: daysAgo(2, 20),
  );
  await add(
    type: TransactionType.expense,
    cents: 3400,
    categoryId: expenses[2].id,
    note: 'Gasolina',
    when: daysAgo(3, 8, 30),
  );

  // Presupuesto global apretado: asi la mascota sale en un estado
  // interesante y la barra muestra color de aviso.
  await backend.budgets.save(BudgetEntity(
    id: IdGenerator.newId(),
    limitCents: 20000,
    createdAt: today,
    updatedAt: today,
  ));
  await backend.budgets.save(BudgetEntity(
    id: IdGenerator.newId(),
    categoryId: expenses[0].id,
    limitCents: 30000,
    createdAt: today,
    updatedAt: today,
  ));

  // Un presupuesto REBASADO a propósito: es el único caso que dibuja la trama
  // diagonal, la pieza que sustituye al rojo de alarma en la paleta monocroma.
  // Sin él, la captura no probaría justamente lo más fácil de romper.
  await backend.budgets.save(BudgetEntity(
    id: IdGenerator.newId(),
    categoryId: expenses[1].id,
    limitCents: 1000,
    createdAt: today,
    updatedAt: today,
  ));

  await backend.flush();
  return backend;
}

/// Carga fuentes de verdad en el entorno de pruebas.
///
/// Sin esto, `flutter test` usa la fuente Ahem, que dibuja cada caracter como
/// un rectangulo negro: las capturas resultantes serian inservibles para
/// juzgar el diseno.
Future<void> _loadRealFonts() async {
  final String? flutterRoot = _resolveFlutterRoot();
  if (flutterRoot == null) return;

  final Directory fonts = Directory(
    '$flutterRoot/bin/cache/artifacts/material_fonts',
  );
  if (!fonts.existsSync()) return;

  Future<void> load(String family, Map<String, String> variants) async {
    final FontLoader loader = FontLoader(family);
    bool any = false;
    for (final MapEntry<String, String> entry in variants.entries) {
      final File file = File('${fonts.path}/${entry.value}');
      if (!file.existsSync()) continue;
      final Uint8List bytes = await file.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', <String, String>{
    'regular': 'roboto-regular.ttf',
    'medium': 'roboto-medium.ttf',
    'bold': 'roboto-bold.ttf',
  });
  await load('MaterialIcons', <String, String>{
    'regular': 'materialicons-regular.otf',
  });

  // Las fuentes propias de la app, leidas de `assets/`: sin ellas las capturas
  // saldrian en Roboto y no reflejarian el diseno real.
  Future<void> loadAsset(String family, String path) async {
    final File file = File(path);
    if (!file.existsSync()) return;
    final Uint8List bytes = await file.readAsBytes();
    await (FontLoader(family)
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
        .load();
  }

  await loadAsset('Archivo', 'assets/fonts/Archivo-Regular.ttf');
  await loadAsset('PinyonScript', 'assets/fonts/PinyonScript-Regular.ttf');
}

String? _resolveFlutterRoot() {
  // `which flutter` no esta disponible aqui, asi que se deduce del ejecutable
  // de Dart que esta corriendo la prueba: vive en <flutter>/bin/cache/dart-sdk.
  final String executable = Platform.resolvedExecutable;
  final int marker = executable.indexOf('bin${Platform.pathSeparator}cache');
  if (marker <= 0) return null;
  return executable.substring(0, marker - 1);
}
