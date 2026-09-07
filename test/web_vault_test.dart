import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/error/failures.dart';
import 'package:hannahswalletapp/core/utils/date_range.dart';
import 'package:hannahswalletapp/core/utils/id_generator.dart';
import 'package:hannahswalletapp/data/backend/app_backend.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/domain/entities/analytics.dart';
import 'package:hannahswalletapp/domain/entities/budget_entity.dart';
import 'package:hannahswalletapp/domain/entities/transaction_entity.dart';
import 'package:hannahswalletapp/domain/entities/wallet_entity.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pruebas del backend de la PWA.
///
/// Se ejecutan sobre `idbFactoryMemory`, la implementacion en memoria de
/// idb_shim: misma API de IndexedDB que en el navegador, sin necesidad de uno.
/// Asi se prueba de verdad el camino completo -cifrar, guardar, descifrar,
/// consultar- en la VM de Dart.
///
/// Es la parte del proyecto que mas necesita cobertura: la version nativa se
/// apoya en SQLite, que ya sabe sumar y filtrar, mientras que aqui esas mismas
/// consultas estan reimplementadas a mano.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));

  late WebBackend backend;

  setUp(() {
    // Un almacen en memoria NUEVO por prueba: sin esto, las bovedas de unas
    // pruebas se colarian en otras.
    backend = WebBackend(store: VaultStore(factory: idbFactoryMemory));
  });

  const String pass = 'contrasena-larga-1';

  Future<void> open() async {
    await backend.initialize();
    await backend.create(passphrase: pass);
  }

  Future<TransactionEntity> addExpense({
    required int cents,
    required DateTime when,
    String? categoryId,
    String? walletId,
  }) async {
    final List<WalletEntity> wallets = await backend.wallets.getWallets();
    final DateTime now = DateTime.now();
    final TransactionEntity tx = TransactionEntity(
      id: IdGenerator.newId(),
      walletId: walletId ?? wallets.first.id,
      categoryId: categoryId,
      type: TransactionType.expense,
      amountCents: cents,
      occurredAt: when,
      createdAt: now,
      updatedAt: now,
    );
    await backend.transactions.create(tx);
    return tx;
  }

  group('ciclo de vida de la boveda', () {
    test('el primer arranque no tiene boveda', () async {
      expect(await backend.initialize(), BackendStatus.needsSetup);
    });

    test('crear la boveda la deja lista y sembrada', () async {
      await open();
      expect(backend.status, BackendStatus.ready);
      expect((await backend.wallets.getWallets()).length, 1);
      expect((await backend.categories.getCategories()).length, greaterThan(10));
    });

    test('rechaza una contrasena demasiado corta', () async {
      await backend.initialize();
      expect(
        () => backend.create(passphrase: 'corta'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('tras bloquear, hay boveda pero esta cerrada', () async {
      await open();
      await backend.lock();
      expect(backend.status, BackendStatus.locked);
      // Pedir datos con la boveda cerrada es un error, no una lista vacia:
      // devolver vacio haria creer que se han perdido.
      expect(() => backend.wallets, throwsA(isA<SecurityFailure>()));
    });

    test('la contrasena correcta reabre la boveda', () async {
      await open();
      await addExpense(cents: 1234, when: DateTime.now());
      await backend.flush();
      await backend.lock();

      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
      expect(backend.status, BackendStatus.ready);
      final List<TransactionView> items =
          await backend.transactions.getRecent();
      expect(items.length, 1);
      expect(items.first.transaction.amountCents, 1234);
    });

    test('la contrasena incorrecta no abre nada y no rompe', () async {
      await open();
      await backend.flush();
      await backend.lock();

      // AES-GCM valida su etiqueta antes de devolver nada, asi que esto es un
      // `false` limpio y no datos corruptos.
      expect(await backend.unlock(passphrase: 'otra-cosa-larga'),
          UnlockOutcome.wrongPassphrase);
      expect(backend.status, BackendStatus.locked);

      // Y la boveda sigue intacta para la contrasena buena.
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
    });

    test('cambiar la contrasena conserva los datos', () async {
      await open();
      await addExpense(cents: 500, when: DateTime.now());
      await backend.flush();

      await backend.changePassphrase(pass, 'nueva-contrasena-2');
      await backend.lock();

      expect(await backend.unlock(passphrase: pass),
          UnlockOutcome.wrongPassphrase);
      expect(await backend.unlock(passphrase: 'nueva-contrasena-2'),
          UnlockOutcome.success);
      expect((await backend.transactions.getRecent()).length, 1);
    });

    test('la contrasena actual equivocada impide el cambio', () async {
      await open();
      expect(
        () => backend.changePassphrase('no-es-esta', 'nueva-contrasena-2'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('wipe deja el almacen como recien instalado', () async {
      await open();
      await backend.wipe();
      expect(await backend.initialize(), BackendStatus.needsSetup);
    });
  });

  group('persistencia', () {
    test('los cambios sobreviven a cerrar y reabrir', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);

      final WebBackend first = WebBackend(store: store);
      await first.initialize();
      await first.create(passphrase: pass);
      final List<WalletEntity> wallets = await first.wallets.getWallets();
      final DateTime now = DateTime.now();
      await first.transactions.create(TransactionEntity(
        id: IdGenerator.newId(),
        walletId: wallets.first.id,
        type: TransactionType.income,
        amountCents: 250000,
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ));
      await first.flush();

      // Instancia nueva sobre el MISMO almacen: simula cerrar la pestana y
      // volver a abrir la PWA.
      final WebBackend second = WebBackend(store: store);
      expect(await second.initialize(), BackendStatus.locked);
      expect(await second.unlock(passphrase: pass), UnlockOutcome.success);
      expect(await second.analytics.getLifetimeBalance(), 250000);
    });
  });

  group('consultas analiticas', () {
    test('el saldo historico no se reinicia con el mes', () async {
      await open();
      final DateTime now = DateTime.now();

      // Un gasto de hace tres meses y otro de hoy.
      await addExpense(cents: 10000, when: DateTime(now.year, now.month - 3, 10));
      await addExpense(cents: 2500, when: now);

      // El saldo acumulado los cuenta los dos, aunque el primero sea de un mes
      // ya cerrado. Ese es justamente el "problema de los reinicios
      // mensuales" que la consulta resuelve.
      expect(await backend.analytics.getLifetimeBalance(), -12500);

      // Los totales del mes en curso, en cambio, solo ven el de hoy.
      final PeriodTotals totals =
          await backend.analytics.getTotals(DateRange.monthOf(now));
      expect(totals.expenseCents, 2500);
    });

    test('las transferencias no alteran el patrimonio total', () async {
      await open();
      final DateTime now = DateTime.now();

      await backend.wallets.create(WalletEntity(
        id: 'w2',
        name: 'Ahorro',
        iconCode: 0xe1a4,
        colorValue: 0xFF5EA269,
        currencyCode: 'EUR',
        initialBalanceCents: 0,
        createdAt: now,
        updatedAt: now,
      ));

      final List<WalletEntity> wallets = await backend.wallets.getWallets();
      final WalletEntity origin =
          wallets.firstWhere((WalletEntity w) => w.id != 'w2');

      await backend.transactions.create(TransactionEntity(
        id: IdGenerator.newId(),
        walletId: origin.id,
        type: TransactionType.income,
        amountCents: 100000,
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ));
      await backend.transactions.create(TransactionEntity(
        id: IdGenerator.newId(),
        walletId: origin.id,
        transferWalletId: 'w2',
        type: TransactionType.transfer,
        amountCents: 30000,
        occurredAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Mover 300 EUR de una cartera a otra no crea ni destruye patrimonio.
      expect(await backend.analytics.getLifetimeBalance(), 100000);

      // Pero si cambia el reparto entre carteras.
      final List<WalletWithBalance> balances =
          await backend.wallets.getWalletsWithBalance();
      final int ahorro = balances
          .firstWhere((WalletWithBalance b) => b.wallet.id == 'w2')
          .balanceCents;
      final int principal = balances
          .firstWhere((WalletWithBalance b) => b.wallet.id == origin.id)
          .balanceCents;
      expect(ahorro, 30000);
      expect(principal, 70000);
    });

    test('el rechazo de un traspaso a la misma cartera', () async {
      await open();
      final List<WalletEntity> wallets = await backend.wallets.getWallets();
      final DateTime now = DateTime.now();

      expect(
        () => backend.transactions.create(TransactionEntity(
          id: IdGenerator.newId(),
          walletId: wallets.first.id,
          transferWalletId: wallets.first.id,
          type: TransactionType.transfer,
          amountCents: 100,
          occurredAt: now,
          createdAt: now,
          updatedAt: now,
        )),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('los borrados logicos no cuentan en los totales', () async {
      await open();
      final TransactionEntity tx =
          await addExpense(cents: 5000, when: DateTime.now());
      expect(await backend.analytics.getLifetimeBalance(), -5000);

      await backend.transactions.softDelete(tx.id);
      expect(await backend.analytics.getLifetimeBalance(), 0);

      await backend.transactions.restore(tx.id);
      expect(await backend.analytics.getLifetimeBalance(), -5000);
    });

    test('el gasto por categoria se agrupa y se ordena', () async {
      await open();
      final DateTime now = DateTime.now();
      final List<String> ids = (await backend.categories.getCategories(
        type: TransactionType.expense,
      ))
          .map((dynamic c) => c.id as String)
          .toList();

      await addExpense(cents: 1000, when: now, categoryId: ids[0]);
      await addExpense(cents: 3000, when: now, categoryId: ids[1]);
      await addExpense(cents: 500, when: now, categoryId: ids[0]);

      final List<dynamic> spending = await backend.analytics
          .getExpenseByCategory(DateRange.monthOf(now));

      expect(spending.length, 2);
      // Ordenado de mayor a menor gasto.
      expect(spending.first.totalCents, 3000);
      expect(spending[1].totalCents, 1500);
      expect(spending[1].entryCount, 2);
    });
  });

  group('presupuestos', () {
    test('la plantilla mensual se hereda en un mes sin presupuesto propio',
        () async {
      await open();
      final DateTime now = DateTime.now();

      // `monthKey: null` = plantilla que vale para todos los meses.
      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        limitCents: 100000,
        createdAt: now,
        updatedAt: now,
      ));

      final BudgetProgress? enero =
          await backend.budgets.getGlobalProgress(DateTime(now.year + 1));
      expect(enero, isNotNull);
      expect(enero!.limitCents, 100000);

      final BudgetProgress? julio =
          await backend.budgets.getGlobalProgress(DateTime(now.year + 1, 7));
      expect(julio!.limitCents, 100000);
    });

    test('el presupuesto puntual del mes gana a la plantilla', () async {
      await open();
      final DateTime now = DateTime.now();

      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        limitCents: 100000,
        createdAt: now,
        updatedAt: now,
      ));
      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        monthKey: DateRange.monthKeyOf(now),
        limitCents: 40000,
        createdAt: now,
        updatedAt: now,
      ));

      // Este mes manda el puntual...
      final BudgetProgress? esteMes = await backend.budgets.getGlobalProgress(now);
      expect(esteMes!.limitCents, 40000);

      // ...y el siguiente vuelve a la plantilla.
      final BudgetProgress? siguiente = await backend.budgets
          .getGlobalProgress(DateTime(now.year, now.month + 1, 15));
      expect(siguiente!.limitCents, 100000);
    });

    test('el consumo global suma todas las categorias', () async {
      await open();
      final DateTime now = DateTime.now();
      final List<String> ids = (await backend.categories.getCategories(
        type: TransactionType.expense,
      ))
          .map((dynamic c) => c.id as String)
          .toList();

      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        limitCents: 100000,
        createdAt: now,
        updatedAt: now,
      ));
      await addExpense(cents: 30000, when: now, categoryId: ids[0]);
      await addExpense(cents: 20000, when: now, categoryId: ids[1]);

      final BudgetProgress p = (await backend.budgets.getGlobalProgress(now))!;
      expect(p.spentCents, 50000);
      expect(p.ratio, closeTo(0.5, 1e-9));
      expect(p.isOverspent, isFalse);
    });

    test('el presupuesto por categoria solo cuenta la suya', () async {
      await open();
      final DateTime now = DateTime.now();
      final List<String> ids = (await backend.categories.getCategories(
        type: TransactionType.expense,
      ))
          .map((dynamic c) => c.id as String)
          .toList();

      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        categoryId: ids[0],
        limitCents: 20000,
        createdAt: now,
        updatedAt: now,
      ));
      await addExpense(cents: 25000, when: now, categoryId: ids[0]);
      await addExpense(cents: 90000, when: now, categoryId: ids[1]);

      final List<BudgetProgress> all =
          await backend.budgets.getProgressForMonth(now);
      expect(all.length, 1);
      expect(all.first.spentCents, 25000);
      expect(all.first.isOverspent, isTrue);
    });

    test('guardar dos veces la misma pareja actualiza en vez de duplicar',
        () async {
      await open();
      final DateTime now = DateTime.now();

      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        limitCents: 50000,
        createdAt: now,
        updatedAt: now,
      ));
      await backend.budgets.save(BudgetEntity(
        id: IdGenerator.newId(),
        limitCents: 70000,
        createdAt: now,
        updatedAt: now,
      ));

      final List<BudgetProgress> all =
          await backend.budgets.getProgressForMonth(now);
      expect(all.length, 1);
      expect(all.first.limitCents, 70000);
    });
  });

  group('portabilidad', () {
    test('exportar e importar reproduce el estado', () async {
      await open();
      final DateTime now = DateTime.now();
      await addExpense(cents: 4200, when: now);
      await addExpense(cents: 1800, when: now);

      final String json = await backend.backup.exportToJsonString();

      final BackupSummary summary = await backend.backup.inspect(json);
      expect(summary.transactionCount, 2);
      // El checksum lo calcula la propia app al exportar, asi que debe cuadrar.
      expect(summary.checksumOk, isTrue);

      // Se borra todo y se restaura.
      await backend.wipe();
      await backend.initialize();
      await backend.create(passphrase: pass);
      expect(await backend.analytics.getLifetimeBalance(), 0);

      await backend.backup.importFromJson(json);
      expect(await backend.analytics.getLifetimeBalance(), -6000);
      expect((await backend.transactions.getRecent()).length, 2);
    });

    test('rechaza una copia de otra aplicacion', () async {
      await open();
      expect(
        () => backend.backup.inspect('{"magic":"otra_app","data":{}}'),
        throwsA(isA<BackupFormatFailure>()),
      );
    });
  });
}
