/// Constantes transversales de Hannah's Wallet.
abstract final class AppConstants {
  static const String appName = "Hannah's Wallet";

  /// Nombre del fichero SQLCipher dentro del directorio privado de la app.
  static const String databaseFileName = 'hannahs_wallet.db';

  /// Versión del esquema SQLite. Subir SIEMPRE que se toque [DatabaseProvider].
  static const int databaseVersion = 1;

  /// Versión del formato del backup JSON. Independiente del esquema SQLite:
  /// permite migrar backups antiguos sin tocar la base.
  static const int backupFormatVersion = 1;

  /// Marca que identifica un JSON como backup legitimo de esta app.
  static const String backupMagic = 'hannahs_wallet_backup';

  // --- Claves de flutter_secure_storage ---
  static const String kDbSecretKey = 'hw_db_secret_v1';
  static const String kDbSaltKey = 'hw_db_salt_v1';
  static const String kAppPinKey = 'hw_app_pin_v1';
  static const String kAppPinSaltKey = 'hw_app_pin_salt_v1';

  // --- Claves de preferencias (tabla app_settings) ---
  static const String kCurrencyCode = 'currency_code';
  static const String kLockEnabled = 'lock_enabled';
  static const String kBiometricEnabled = 'biometric_enabled';
  static const String kOnboardingDone = 'onboarding_done';
  static const String kMascotEnabled = 'mascot_enabled';

  /// Minutos de inactividad antes del bloqueo automático. 0 = nunca.
  static const String kAutoLockMinutes = 'auto_lock_minutes';

  /// Iteraciones PBKDF2 para derivar la clave de SQLCipher.
  ///
  /// SQLCipher aplica su propio KDF por encima; estas iteraciones protegen el
  /// secreto en reposo en el Keystore/Keychain sin castigar el arranque.
  static const int pbkdf2IterationsDb = 120000;

  /// Iteraciones PBKDF2 para el PIN de la app. Mas alto porque el espacio de
  /// busqueda de un PIN de 4-6 dígitos es ridiculamente pequeño.
  static const int pbkdf2IterationsPin = 200000;

  /// Iteraciones PBKDF2 de la bóveda web.
  ///
  /// Mas altas que las del móvil (310 000 frente a 120 000) por una razon de
  /// peso: aquí la entropia la pone una persona eligiendo una contraseña, no
  /// un generador aleatorio, y el blob cifrado esta en IndexedDB al alcance de
  /// cualquiera que abra las herramientas del navegador. Es la cifra que
  /// recomienda OWASP para PBKDF2-HMAC-SHA256.
  ///
  /// El coste lo absorbe la Web Crypto API del navegador, que ejecuta el KDF
  /// en código nativo.
  static const int pbkdf2IterationsWeb = 310000;

  /// Longitud minima de la contraseña maestra de la PWA.
  ///
  /// Ocho caracteres, no cuatro dígitos como el PIN del móvil: alli el
  /// Keystore limita los intentos por hardware, pero aquí un atacante con el
  /// blob puede probar sin freno en su propio equipo.
  static const int minPassphraseLength = 8;

  /// Nombre de la base IndexedDB y de su almacen.
  static const String webVaultDbName = 'hannahs_wallet_vault';
  static const String webVaultStoreName = 'vault';
  static const String webVaultRecordKey = 'main';

  /// Registro de intentos fallidos. Va fuera de la bóveda: comprobarlo no
  /// puede exigir descifrar justamente lo que se intenta proteger.
  static const String webVaultAttemptsKey = 'attempts';

  /// A partir de cuántos fallos seguidos se empieza a penalizar.
  static const int maxFreeAttempts = 5;

  /// Tope de la espera entre intentos. Cinco minutos hacen inviable la fuerza
  /// bruta sin castigar de más a quien simplemente se equivocó al teclear.
  static const Duration maxLockout = Duration(minutes: 5);

  /// Inactividad tras la cual la app se bloquea sola.
  static const Duration autoLockDelay = Duration(minutes: 3);

  static const int keyLengthBytes = 32;
  static const int saltLengthBytes = 16;

  /// Umbral a partir del cual la mascota pasa a estado de alerta.
  static const double budgetAlertThreshold = 0.9;

  /// Umbral a partir del cual la mascota empieza a preocuparse.
  static const double budgetWarningThreshold = 0.7;
}
