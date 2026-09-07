import '../../core/error/failures.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/dao/analytics_dao.dart';
import '../datasources/local/dao/budget_dao.dart';
import '../datasources/local/dao/category_dao.dart';
import '../datasources/local/dao/recurring_dao.dart';
import '../datasources/local/dao/settings_dao.dart';
import '../datasources/local/dao/transaction_dao.dart';
import '../datasources/local/dao/wallet_dao.dart';
import '../datasources/local/data_change_bus.dart';
import '../datasources/local/database_provider.dart';
import '../repositories/repository_impls.dart';
import '../security/encryption_key_manager.dart';
import '../services/backup_service.dart';
import 'app_backend.dart';
import 'web/biometric_unlock.dart';

/// Backend de iOS y Android: SQLCipher con la clave en el Keychain/Keystore.
///
/// No pide contraseña porque no le hace falta: el sistema operativo custodia la
/// clave en almacenamiento respaldado por hardware y la app la recupera sola.
/// Lo que protege la PANTALLA es el bloqueo biométrico, que es una capa aparte
/// (ver `AppLockService`).
///
/// Este fichero es el único sitio del proyecto que conoce a la vez todos los
/// DAO, y solo se compila en plataformas nativas: el build web ni lo mira,
/// gracias al import condicional de `backend_factory.dart`. Esa separación es
/// necesaria porque `sqflite_sqlcipher` no tiene implementación web y su sola
/// presencia rompería la compilación del bundle.
class NativeBackend implements AppBackend {
  NativeBackend({DataChangeBus? bus, EncryptionKeyManager? keyManager})
      : _bus = bus ?? DataChangeBus(),
        _database = DatabaseProvider(keyManager ?? EncryptionKeyManager());

  final DataChangeBus _bus;
  final DatabaseProvider _database;

  BackendStatus _status = BackendStatus.needsSetup;

  @override
  DataChangeBus get changeBus => _bus;

  /// Acceso al proveedor para las operaciones de bajo nivel de Ajustes
  /// (compactar, borrado total).
  DatabaseProvider get databaseProvider => _database;

  @override
  String get displayName => 'SQLCipher';

  /// Nunca: la clave la guarda el sistema operativo.
  @override
  bool get requiresPassphrase => false;

  @override
  BackendStatus get status => _status;

  @override
  Future<BackendStatus> initialize() async {
    // Abrir la base ya la crea y la siembra si no existia, de modo que el
    // estado resultante siempre es `ready`.
    await _database.database();
    _status = BackendStatus.ready;
    return _status;
  }

  @override
  Future<void> create({String? passphrase}) => initialize();

  @override
  Future<UnlockOutcome> unlock({String? passphrase}) async {
    await initialize();
    return UnlockOutcome.success;
  }

  /// Sin penalización: aquí no hay contraseña que adivinar. Los intentos los
  /// limita el PIN de la app a través de `LockGate`, y por debajo el propio
  /// Keystore del sistema.
  @override
  Future<Duration> lockoutRemaining() async => Duration.zero;

  // --------------------------------------------------------- Biometría
  //
  // En móvil la biometría NO desbloquea el cifrado: la clave la custodia el
  // Keychain/Keystore y la app la recupera sola. Lo que hace Face ID aquí es
  // tapar la pantalla, y de eso se encarga `LockGate`. Por eso este backend
  // declara que no ofrece desbloqueo biométrico del almacén: sería mentir
  // sobre lo que protege.

  @override
  Future<bool> supportsBiometricUnlock() async => false;

  @override
  Future<BiometricStatus> diagnoseBiometrics() async =>
      BiometricStatus.noWebAuthn;

  @override
  bool get hasBiometricUnlock => false;

  @override
  Future<void> enableBiometricUnlock() async {
    throw const SecurityFailure(
      'En móvil el bloqueo biométrico se configura en Ajustes > Seguridad.',
    );
  }

  @override
  Future<void> disableBiometricUnlock() async {}

  @override
  Future<UnlockOutcome> unlockWithBiometrics() async =>
      UnlockOutcome.unavailable;

  @override
  Future<void> lock() async {
    // El cierre de sesión en nativo lo gestiona `AppLockNotifier` sobre la UI.
    // La base puede seguir abierta: el fichero ya esta cifrado en disco.
  }

  @override
  Future<void> changePassphrase(String current, String next) async {
    throw const SecurityFailure(
      'En móvil no hay contraseña maestra: la clave la custodia el sistema.',
    );
  }

  @override
  Future<void> wipe() async {
    await _database.wipeEverything();
    _status = BackendStatus.needsSetup;
  }

  @override
  Future<void> flush() => _database.checkpoint();

  @override
  WalletRepository get wallets =>
      WalletRepositoryImpl(WalletDao(_database), _bus);

  @override
  CategoryRepository get categories =>
      CategoryRepositoryImpl(CategoryDao(_database), _bus);

  @override
  TransactionRepository get transactions =>
      TransactionRepositoryImpl(TransactionDao(_database), _bus);

  @override
  BudgetRepository get budgets =>
      BudgetRepositoryImpl(BudgetDao(_database), _bus);

  @override
  AnalyticsRepository get analytics => AnalyticsRepositoryImpl(
        AnalyticsDao(_database),
        BudgetDao(_database),
        SettingsDao(_database),
      );

  @override
  SettingsRepository get settings =>
      SettingsRepositoryImpl(SettingsDao(_database), _bus);

  @override
  RecurringRepository get recurring => RecurringRepositoryImpl(
        RecurringDao(_database),
        TransactionDao(_database),
        _bus,
      );

  @override
  BackupPort get backup => _NativeBackupPort(BackupService(_database, _bus));
}

/// Adapta el `BackupService` de SQLCipher al puerto comun.
class _NativeBackupPort implements BackupPort {
  _NativeBackupPort(this._service);

  final BackupService _service;

  @override
  Future<Map<String, dynamic>> buildBackupMap() => _service.buildBackupMap();

  @override
  Future<String> exportToJsonString() => _service.exportToJsonString();

  @override
  Future<BackupSummary> inspect(String jsonSource) async {
    final BackupPreview preview = await _service.inspect(jsonSource);
    return BackupSummary(
      counts: preview.counts,
      checksumOk: preview.checksumOk,
      exportedAt: preview.exportedAt,
      formatVersion: preview.formatVersion,
    );
  }

  @override
  Future<BackupImportResult> importFromJson(
    String jsonSource, {
    bool replaceExisting = true,
  }) async {
    final ImportReport report = await _service.importFromJson(
      jsonSource,
      strategy:
          replaceExisting ? ImportStrategy.replace : ImportStrategy.merge,
    );
    return BackupImportResult(
      inserted: report.inserted,
      skipped: report.skipped,
      exportedAt: report.exportedAt,
    );
  }
}
