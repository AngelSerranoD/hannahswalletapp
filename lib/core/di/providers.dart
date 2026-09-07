import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend/app_backend.dart';
import '../../data/backend/backend_factory.dart';
import '../../data/datasources/local/data_change_bus.dart';
import '../../data/services/lock_gate.dart';
import '../../domain/repositories/repositories.dart';

/// Grafo de dependencias de la app.
///
/// Se usa Riverpod como contenedor de inyección en lugar de un service locator
/// global (`GetIt` y compañía) por dos razones concretas:
///
///  * cada dependencia se declara con su tipo y se resuelve en compilacion, no
///    con una cadena magica que revienta en tiempo de ejecucion si se escribe
///    mal;
///  * en los tests se sustituye cualquier nodo con `overrideWith` sin tocar
///    estado global ni acordarse de limpiarlo entre pruebas.
///
/// TODO lo que hay debajo cuelga de [appBackendProvider], que según la
/// plataforma es SQLCipher (móvil) o la bóveda cifrada de IndexedDB (PWA). La
/// capa de presentacion no distingue una de otra.

// ------------------------------------------------------------- Plataforma

/// El backend de datos de esta plataforma. Se crea una sola vez.
final Provider<AppBackend> appBackendProvider = Provider<AppBackend>((Ref ref) {
  final AppBackend backend = createAppBackend();
  // Al desmontar el contenedor se vuelca lo pendiente: en web puede haber
  // cambios esperando en la ventana de agrupación de escrituras.
  ref.onDispose(() => unawaited(backend.flush()));
  return backend;
});

/// Bloqueo de pantalla: biometría y PIN en móvil, inexistente en la PWA.
final Provider<LockGate> lockGateProvider =
    Provider<LockGate>((Ref ref) => createLockGate());

final Provider<DataChangeBus> dataChangeBusProvider =
    Provider<DataChangeBus>((Ref ref) => ref.watch(appBackendProvider).changeBus);

// ------------------------------------------- Estado de la sesión de datos

/// Estado del almacen: sin crear, bloqueado o listo.
///
/// En móvil pasa a `ready` en cuanto se abre la base. En la PWA se queda en
/// `locked` hasta que se introduce la contraseña maestra correcta, y TODOS los
/// repositorios lo observan: mientras no este `ready`, pedirlos es un error.
class BackendSessionNotifier extends Notifier<BackendStatus> {
  @override
  BackendStatus build() => ref.watch(appBackendProvider).status;

  AppBackend get _backend => ref.read(appBackendProvider);

  Future<BackendStatus> initialize() async {
    state = await _backend.initialize();
    return state;
  }

  /// Crea el almacen por primera vez.
  Future<void> create({String? passphrase}) async {
    await _backend.create(passphrase: passphrase);
    state = _backend.status;
  }

  /// Abre el almacen con contraseña.
  Future<UnlockOutcome> unlock({String? passphrase}) async {
    final UnlockOutcome outcome = await _backend.unlock(passphrase: passphrase);
    state = _backend.status;
    return outcome;
  }

  /// Abre el almacen con Face ID / Touch ID.
  Future<UnlockOutcome> unlockWithBiometrics() async {
    final UnlockOutcome outcome = await _backend.unlockWithBiometrics();
    state = _backend.status;
    return outcome;
  }

  /// Lo que queda de penalización por intentos fallidos.
  Future<Duration> lockoutRemaining() => _backend.lockoutRemaining();

  Future<void> enableBiometricUnlock() async {
    await _backend.enableBiometricUnlock();
    ref.invalidateSelf();
  }

  Future<void> disableBiometricUnlock() async {
    await _backend.disableBiometricUnlock();
    ref.invalidateSelf();
  }

  Future<void> lock() async {
    await _backend.lock();
    state = _backend.status;
  }

  Future<void> changePassphrase(String current, String next) =>
      _backend.changePassphrase(current, next);

  Future<void> wipe() async {
    await _backend.wipe();
    state = _backend.status;
  }

  Future<void> flush() => _backend.flush();
}

final NotifierProvider<BackendSessionNotifier, BackendStatus>
    backendSessionProvider =
    NotifierProvider<BackendSessionNotifier, BackendStatus>(
        BackendSessionNotifier.new);

/// Contador de versión de los datos.
///
/// Cada escritura confirmada incrementa este entero, y todos los providers de
/// lectura lo observan. Es el mecanismo que mantiene la UI al día sin sondeos.
///
/// Se modela como entero y no como `Stream<void>`: Riverpod compara los
/// estados con `==` y dos `AsyncData<void>(null)` consecutivos son iguales, así
/// que un stream de eventos vacios no volvería a notificar a nadie.
final NotifierProvider<DataRevisionNotifier, int> dataRevisionProvider =
    NotifierProvider<DataRevisionNotifier, int>(DataRevisionNotifier.new);

class DataRevisionNotifier extends Notifier<int> {
  @override
  int build() {
    final DataChangeBus bus = ref.watch(dataChangeBusProvider);
    final StreamSubscription<void> sub =
        bus.changes.listen((_) => state = state + 1);
    ref.onDispose(sub.cancel);
    return 0;
  }

  /// Fuerza un refresco general. Lo usa la importación de backups.
  void bump() => state = state + 1;
}

// ----------------------------------------------------------- Repositorios
//
// Cada uno observa `backendSessionProvider`: al desbloquear la bóveda web hay
// que reconstruirlos, porque antes de eso no existia sesión de la que colgar.

final Provider<WalletRepository> walletRepositoryProvider =
    Provider<WalletRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).wallets;
});

final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).categories;
});

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).transactions;
});

final Provider<BudgetRepository> budgetRepositoryProvider =
    Provider<BudgetRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).budgets;
});

final Provider<AnalyticsRepository> analyticsRepositoryProvider =
    Provider<AnalyticsRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).analytics;
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).settings;
});

final Provider<RecurringRepository> recurringRepositoryProvider =
    Provider<RecurringRepository>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).recurring;
});

/// Exportación e importación del JSON. Mismo formato en las dos plataformas.
final Provider<BackupPort> backupProvider = Provider<BackupPort>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).backup;
});
