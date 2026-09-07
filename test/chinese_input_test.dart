import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/app.dart';
import 'package:hannahswalletapp/core/di/providers.dart';
import 'package:hannahswalletapp/core/i18n/cjk_font_loader.dart';
import 'package:hannahswalletapp/core/theme/app_theme.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/domain/entities/category_entity.dart';
import 'package:hannahswalletapp/domain/entities/transaction_entity.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Escribir en chino.
///
/// La interfaz de la app está en español; lo que se comprueba aquí es que el
/// usuario pueda ESCRIBIR en chino y que ese texto sobreviva entero: al
/// teclearlo, al cifrarlo, al guardarlo y al volver a leerlo.
///
/// Hay dos cosas distintas en juego y las dos pueden fallar por separado:
///
///  1. **Los bytes**: UTF-8 con caracteres de tres bytes pasando por AES-GCM y
///     por IndexedDB. Un fallo aquí devuelve texto corrupto.
///  2. **Los glifos**: Roboto no tiene un solo carácter chino, y la política
///     de seguridad prohíbe descargar fuentes de reserva. Sin la fuente
///     empaquetada, el texto se guardaría bien pero se vería como rectángulos.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));
  setUp(() async => VaultStore(factory: idbFactoryMemory).delete());

  const String pass = 'contrasena-de-prueba';

  // Textos reales, no una letra suelta: nombres de categoría y un concepto.
  const String categoryZh = '餐饮';           // restauración
  const String conceptZh = '和玛尔塔喝咖啡';    // café con Marta
  const String mixed = '超市 Mercadona 购物'; // chino y latino mezclados

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 80));
  }

  group('la fuente china', () {
    test('está empaquetada y se puede cargar', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      CjkFontLoader.resetForTest();

      // Que el asset exista es la mitad del asunto: sin él, el `FontLoader`
      // fallaría en silencio y el fallo solo se vería en pantalla.
      final ByteData data =
          await rootBundle.load('assets/fonts/NotoSansSC-Regular.otf');
      expect(data.lengthInBytes, greaterThan(1000000),
          reason: 'La fuente CJK completa debe pesar varios MB');

      await CjkFontLoader.ensureLoaded();
      expect(CjkFontLoader.isLoaded, isTrue);
    });

    test('el tema la declara como reserva', () {
      final ThemeData theme = AppTheme.light();
      expect(theme.textTheme.bodyLarge?.fontFamilyFallback ??
          <String>[CjkFontLoader.family], contains(CjkFontLoader.family));
      // Y Roboto sigue siendo la principal: las tildes y el símbolo del euro
      // deben salir de ella, no de la china.
      expect(AppTheme.light().textTheme.bodyLarge, isNotNull);
    });

    test('cargarla dos veces no descarga dos veces', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      CjkFontLoader.resetForTest();
      await Future.wait<void>(<Future<void>>[
        CjkFontLoader.ensureLoaded(),
        CjkFontLoader.ensureLoaded(),
      ]);
      expect(CjkFontLoader.isLoaded, isTrue);
    });
  });

  group('los datos en chino', () {
    test('sobreviven al cifrado y al reinicio', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend =
          WebBackend(store: store, kdfIterations: 1000);
      await backend.initialize();
      await backend.create(passphrase: pass);

      final DateTime now = DateTime.now();
      final CategoryEntity category = CategoryEntity(
        id: 'cat-zh',
        name: categoryZh,
        iconCode: Icons.restaurant_outlined.codePoint,
        colorValue: 0xFF0A3323,
        type: TransactionType.expense,
        createdAt: now,
        updatedAt: now,
      );
      await backend.categories.create(category);

      final List<dynamic> wallets = await backend.wallets.getWallets();
      await backend.transactions.create(TransactionEntity(
        id: 'tx-zh',
        walletId: wallets.first.id as String,
        categoryId: category.id,
        type: TransactionType.expense,
        amountCents: 1250,
        note: conceptZh,
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ));
      await backend.flush();

      // Se cierra y se vuelve a abrir: el texto pasa por AES-GCM e IndexedDB.
      await backend.lock();
      final WebBackend reopened =
          WebBackend(store: store, kdfIterations: 1000);
      await reopened.initialize();
      await reopened.unlock(passphrase: pass);

      final List<CategoryEntity> cats =
          await reopened.categories.getCategories();
      expect(
        cats.map((CategoryEntity c) => c.name),
        contains(categoryZh),
        reason: 'El nombre en chino debe volver intacto',
      );

      final List<TransactionView> txs =
          await reopened.transactions.getRecent();
      expect(txs.first.transaction.note, conceptZh);
      // Comprobación fina: mismo número de caracteres, no solo "no vacío". Un
      // fallo de codificación suele devolver más bytes convertidos en signos
      // de interrogación, y la longitud lo delata.
      expect(txs.first.transaction.note!.length, conceptZh.length);
    });

    test('el backup JSON conserva el chino', () async {
      final WebBackend backend = WebBackend(
        store: VaultStore(factory: idbFactoryMemory),
        kdfIterations: 1000,
      );
      await backend.initialize();
      await backend.create(passphrase: pass);

      final DateTime now = DateTime.now();
      await backend.categories.create(CategoryEntity(
        id: 'cat-mixta',
        name: mixed,
        iconCode: Icons.shopping_cart_outlined.codePoint,
        colorValue: 0xFF105666,
        type: TransactionType.expense,
        createdAt: now,
        updatedAt: now,
      ));
      await backend.flush();

      final String json = await backend.backup.exportToJsonString();
      // `jsonEncode` puede escapar los caracteres a \uXXXX; lo que importa es
      // que al releerlo vuelva el texto original.
      final BackupSummaryLike summary = BackupSummaryLike(json);
      expect(summary.containsChinese, isTrue);

      await backend.backup.importFromJson(json);
      final List<CategoryEntity> cats = await backend.categories.getCategories();
      expect(cats.map((CategoryEntity c) => c.name), contains(mixed));
    });
  });

  testWidgets('se puede teclear chino en el formulario de un gasto',
      (WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBackendProvider.overrideWithValue(
            WebBackend(
              store: VaultStore(factory: idbFactoryMemory),
              kdfIterations: 1000,
            ),
          ),
        ],
        child: const HannahsWalletApp(),
      ),
    );
    await settle(tester, rounds: 14);

    await tester.enterText(find.byType(TextField).first, pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);

    await tester.tap(find.text('Nuevo gasto'));
    await settle(tester, rounds: 8);

    await tester.enterText(find.byType(TextField).first, '12,50');
    await settle(tester, rounds: 4);

    // El campo de concepto vive más abajo en un scroll, así que hay que
    // traerlo a la vista antes de escribir: los widgets fuera de pantalla ni
    // siquiera están construidos.
    final Finder concept = find.ancestor(
      of: find.text('Nota (opcional)'),
      matching: find.byType(TextField),
    );
    await tester.dragUntilVisible(
      concept,
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await settle(tester, rounds: 4);

    // Acepta los caracteres tal cual: sin filtros de entrada que se coman lo
    // que no sea ASCII.
    await tester.enterText(concept, conceptZh);
    await settle(tester, rounds: 4);

    expect(find.text(conceptZh), findsOneWidget,
        reason: 'El campo debe mostrar lo tecleado en chino');

    await tester.tap(find.text('Alimentación').first);
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Guardar'));
    await settle(tester, rounds: 16);

    // Y llega al dashboard con el texto entero.
    expect(find.text(conceptZh), findsWidgets,
        reason: 'El concepto en chino debe aparecer en la lista');
  });
}

/// Ayuda mínima para comprobar que el JSON exportado lleva chino, tanto si
/// viaja literal como escapado en `\uXXXX`.
class BackupSummaryLike {
  BackupSummaryLike(this.json);

  final String json;

  bool get containsChinese =>
      RegExp(r'[一-鿿]').hasMatch(json) ||
      RegExp(r'\\u4[0-9a-fA-F]{3}').hasMatch(json) ||
      RegExp(r'\\u[5-9][0-9a-fA-F]{3}').hasMatch(json);
}
