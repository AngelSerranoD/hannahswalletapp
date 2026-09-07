import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';

/// Custodia de la clave AES que cifra la base SQLCipher.
///
/// Modelo de amenaza que resuelve: alguien con acceso al sistema de ficheros
/// (backup ADB, móvil rooteado, tarjeta extraida) NO debe poder leer los
/// movimientos. El fichero `.db` en disco es ruido sin la clave, y la clave
/// vive en el Keystore de Android / Keychain de iOS, respaldado por hardware.
///
/// Como funciona, paso a paso:
///
///  1. En el primer arranque se genera un *secreto maestro* de 32 bytes con
///     [Random.secure] (CSPRNG del sistema) y un *salt* de 16 bytes.
///  2. Ambos se guardan en `flutter_secure_storage`. Nunca salen de ahi.
///  3. La passphrase real de SQLCipher se *deriva* con PBKDF2-HMAC-SHA256
///     ([AppConstants.pbkdf2IterationsDb] iteraciones) sobre secreto + salt.
///
/// El paso 3 puede parecer redundante teniendo ya 32 bytes aleatorios, y lo
/// sería si el Keystore fuese infalible. No lo es: en dispositivos sin
/// StrongBox el material puede acabar en almacenamiento de software. El KDF
/// añade un coste de trabajo fijo por intento, de modo que quien extraiga el
/// blob cifrado aun tiene que pagar 120 000 iteraciones por prueba. Además,
/// permite rotar la passphrase de la base cambiando solo el salt.
///
/// Todo esto es invisible: el usuario nunca escribe una contraseña de base.
class EncryptionKeyManager {
  EncryptionKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage;

  final FlutterSecureStorage _storage;

  /// Cache de proceso: PBKDF2 cuesta cientos de milisegundos a proposito.
  /// Derivarla en cada `openDatabase` haría que la app tardase en arrancar.
  String? _cachedPassphrase;

  /// En Android, `AndroidOptions()` ya usa por defecto AES-GCM con la clave
  /// envuelta en RSA dentro del Keystore. En iOS se elige
  /// `first_unlock_this_device`: el material queda disponible tras el primer
  /// desbloqueo del arranque -para que la app pueda abrirse sin pedir nada- y
  /// NO viaja en las copias de iCloud, que es justo lo que se quiere de una
  /// clave ligada a este dispositivo.
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Devuelve la passphrase de SQLCipher, creando el material si es el primer
  /// arranque. Idempotente y seguro de llamar en paralelo desde providers.
  Future<String> obtainDatabasePassphrase() async {
    final String? cached = _cachedPassphrase;
    if (cached != null) return cached;

    try {
      final Uint8List secret = await _readOrCreate(
        AppConstants.kDbSecretKey,
        AppConstants.keyLengthBytes,
      );
      final Uint8List salt = await _readOrCreate(
        AppConstants.kDbSaltKey,
        AppConstants.saltLengthBytes,
      );

      final Uint8List derived = await _derive(
        secret: secret,
        salt: salt,
        iterations: AppConstants.pbkdf2IterationsDb,
      );

      // SQLCipher recibe la clave como texto: base64 mantiene los 256 bits
      // intactos y evita bytes nulos que romperian la cadena C.
      final String passphrase = base64Url.encode(derived);
      _cachedPassphrase = passphrase;
      return passphrase;
    } on AppFailure {
      rethrow;
    } catch (error, stack) {
      throw SecurityFailure(
        'No se pudo obtener la clave de cifrado del almacenamiento seguro.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  /// `true` si ya existe material criptográfico, es decir, si la base ya fue
  /// creada alguna vez en este dispositivo.
  Future<bool> hasExistingKey() async {
    final String? secret = await _storage.read(key: AppConstants.kDbSecretKey);
    return secret != null && secret.isNotEmpty;
  }

  /// Deriva un hash de PIN con su propio salt. No guarda nada: el llamante
  /// decide si lo compara o lo persiste.
  Future<String> derivePinHash(String pin, Uint8List salt) async {
    final Uint8List derived = await _derive(
      secret: Uint8List.fromList(utf8.encode(pin)),
      salt: salt,
      iterations: AppConstants.pbkdf2IterationsPin,
    );
    return base64.encode(derived);
  }

  /// Borra TODO el material criptográfico. La base cifrada queda ilegible para
  /// siempre; usar solo junto con el borrado del fichero.
  Future<void> destroyKeyMaterial() async {
    _cachedPassphrase = null;
    await _storage.delete(key: AppConstants.kDbSecretKey);
    await _storage.delete(key: AppConstants.kDbSaltKey);
    await _storage.delete(key: AppConstants.kAppPinKey);
    await _storage.delete(key: AppConstants.kAppPinSaltKey);
  }

  Future<Uint8List> _readOrCreate(String key, int lengthBytes) async {
    final String? stored = await _storage.read(key: key);
    if (stored != null && stored.isNotEmpty) {
      return Uint8List.fromList(base64.decode(stored));
    }
    final Uint8List fresh = randomBytes(lengthBytes);
    await _storage.write(key: key, value: base64.encode(fresh));
    return fresh;
  }

  /// PBKDF2 fuera del hilo de UI.
  ///
  /// 120 000 iteraciones bloquean el isolate principal el tiempo suficiente
  /// para que se noten frames perdidos en el splash, así que se ejecuta en un
  /// isolate desechable. Solo cruzan la frontera listas de bytes.
  static Future<Uint8List> _derive({
    required Uint8List secret,
    required Uint8List salt,
    required int iterations,
  }) {
    return Isolate.run(() => _pbkdf2Sync(secret, salt, iterations));
  }

  static Future<Uint8List> _pbkdf2Sync(
    Uint8List secret,
    Uint8List salt,
    int iterations,
  ) async {
    final Pbkdf2 kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: AppConstants.keyLengthBytes * 8,
    );
    final SecretKey key = await kdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Bytes aleatorios de calidad criptográfica.
  static Uint8List randomBytes(int length) {
    final Random rng = Random.secure();
    final Uint8List out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }
}
