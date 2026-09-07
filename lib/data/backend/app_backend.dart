import '../../domain/repositories/repositories.dart';
import '../datasources/local/data_change_bus.dart';
import 'web/biometric_unlock.dart';

/// En que punto esta la sesión de datos.
enum BackendStatus {
  /// Primer arranque: no hay almacen todavia. En web hay que crear la
  /// contraseña maestra; en nativo esto no llega a verse porque la clave se
  /// genera sola.
  needsSetup,

  /// El almacen existe pero esta cerrado. En web, hasta que no se introduce la
  /// contraseña correcta, lo guardado son bytes sin sentido.
  locked,

  /// Datos disponibles.
  ready,
}

/// Contrato de la capa de persistencia, sea cual sea la plataforma.
///
/// Existe porque Hannah's Wallet corre en dos mundos muy distintos:
///
///  * **iOS/Android nativo**: SQLCipher cifra el fichero y la clave vive en el
///    Keychain/Keystore del dispositivo. El usuario no escribe nada.
///  * **PWA**: no hay Keystore ni SQLCipher compilado para web. La única raiz
///    de confianza posible es una contraseña que el usuario recuerde, así que
///    el almacen es un blob AES-GCM en IndexedDB cuya clave se deriva de ella.
///
/// Toda la capa de presentacion habla con los repositorios de esta interfaz y
/// no sabe cual de los dos mundos tiene debajo.
abstract interface class AppBackend {
  /// Nombre corto para diagnostico ("SQLCipher", "Bóveda web").
  String get displayName;

  /// Pulso de "algo ha cambiado", para que la UI se refresque tras escribir.
  DataChangeBus get changeBus;

  /// `true` si el desbloqueo depende de una contraseña que escribe el usuario.
  /// La UI lo consulta para decidir si ensena la pantalla de contraseña y para
  /// avisar de que no hay forma de recuperarla.
  bool get requiresPassphrase;

  BackendStatus get status;

  /// Prepara el almacen. En nativo abre la base cifrada; en web solo comprueba
  /// si ya existe una bóveda, sin descifrarla.
  Future<BackendStatus> initialize();

  /// Crea el almacen por primera vez. [passphrase] solo se usa cuando
  /// [requiresPassphrase] es `true`.
  Future<void> create({String? passphrase});

  /// Abre el almacen existente.
  ///
  /// Devuelve el motivo exacto del fallo en lugar de un `bool`: la interfaz
  /// necesita distinguir "contraseña incorrecta" de "estás bloqueado por
  /// intentos fallidos", porque el mensaje y lo que puede hacer el usuario son
  /// muy distintos.
  Future<UnlockOutcome> unlock({String? passphrase});

  /// Tiempo que queda de penalización por intentos fallidos.
  Future<Duration> lockoutRemaining();

  // ------------------------------------------------------------ Biometría

  /// `true` si esta plataforma puede proteger la clave con biometría de forma
  /// que sirva PARA CIFRAR, no solo para enseñar un diálogo.
  Future<bool> supportsBiometricUnlock();

  /// Motivo por el que la biometría está o no disponible, para poder
  /// explicárselo al usuario en lugar de enseñarle un interruptor gris.
  Future<BiometricStatus> diagnoseBiometrics();

  /// `true` si el usuario ya la ha activado.
  bool get hasBiometricUnlock;

  /// Registra la biometría. Requiere la sesión abierta.
  Future<void> enableBiometricUnlock();

  /// La retira. Nunca deja la bóveda sin ninguna forma de abrirse.
  Future<void> disableBiometricUnlock();

  /// Abre la bóveda con biometría.
  Future<UnlockOutcome> unlockWithBiometrics();

  /// Cierra la sesión y borra de memoria todo lo descifrado.
  Future<void> lock();

  /// Cambia la contraseña maestra. Solo tiene sentido cuando
  /// [requiresPassphrase] es `true`; en móvil no hay contraseña que cambiar
  /// porque la clave la custodia el sistema.
  Future<void> changePassphrase(String current, String next);

  /// Destruye almacen y claves. Irreversible.
  Future<void> wipe();

  /// Fuerza el volcado de lo pendiente. Se llama antes de exportar y cuando la
  /// app pasa a segundo plano.
  Future<void> flush();

  WalletRepository get wallets;
  CategoryRepository get categories;
  TransactionRepository get transactions;
  BudgetRepository get budgets;
  AnalyticsRepository get analytics;
  SettingsRepository get settings;
  RecurringRepository get recurring;

  /// Exporta e importa el JSON de copia de seguridad.
  ///
  /// El formato es EL MISMO en las dos plataformas: es lo que permite anotar
  /// gastos en el móvil y llevarselos a la PWA, o al reves.
  BackupPort get backup;
}

/// Resultado de un intento de apertura.
enum UnlockOutcome {
  success,

  /// La contraseña no era la correcta.
  wrongPassphrase,

  /// Demasiados intentos fallidos: hay que esperar.
  lockedOut,

  /// El usuario cerró el diálogo del sistema. No cuenta como fallo.
  cancelled,

  /// La vía de desbloqueo pedida no está disponible en este dispositivo.
  unavailable,
}

/// Puerto de portabilidad de datos, comun a las dos plataformas.
abstract interface class BackupPort {
  Future<Map<String, dynamic>> buildBackupMap();
  Future<String> exportToJsonString();
  Future<BackupSummary> inspect(String jsonSource);
  Future<BackupImportResult> importFromJson(
    String jsonSource, {
    bool replaceExisting = true,
  });
}

/// Lo que se sabe de una copia antes de restaurarla.
class BackupSummary {
  const BackupSummary({
    required this.counts,
    required this.checksumOk,
    this.exportedAt,
    this.formatVersion = 0,
  });

  final Map<String, int> counts;
  final bool checksumOk;
  final DateTime? exportedAt;
  final int formatVersion;

  int get transactionCount => counts['transactions'] ?? 0;
  int get walletCount => counts['wallets'] ?? 0;
  int get categoryCount => counts['categories'] ?? 0;
  int get budgetCount => counts['budgets'] ?? 0;
}

/// Resultado de una restauración.
class BackupImportResult {
  const BackupImportResult({
    required this.inserted,
    required this.skipped,
    this.exportedAt,
  });

  final Map<String, int> inserted;
  final Map<String, int> skipped;
  final DateTime? exportedAt;

  int get totalInserted => inserted.values.fold(0, (int a, int b) => a + b);
  int get totalSkipped => skipped.values.fold(0, (int a, int b) => a + b);
}
