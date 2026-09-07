import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../security/encryption_key_manager.dart';

/// Resultado de un intento de desbloqueo.
enum UnlockResult {
  success,
  failed,

  /// El usuario cancelo el dialogo del sistema. No es un fallo: no debe contar
  /// como intento fallido ni mostrar error en rojo.
  cancelled,

  /// El dispositivo no tiene biometría utilizable ahora mismo.
  unavailable,
}

/// Bloqueo de la app: biometría del sistema con PIN de respaldo.
///
/// POR QUE EXISTE, si la base ya va cifrada: SQLCipher protege el FICHERO, no
/// la PANTALLA. La clave se lee sola del Keystore al arrancar (así lo pedia el
/// diseno: cifrado invisible), así que cualquiera que coja el móvil
/// desbloqueado ve todos los movimientos. Esta capa cubre justo ese hueco.
///
/// El PIN NO se guarda. Se guarda su derivacion PBKDF2 con salt propio y
/// 200 000 iteraciones. Un PIN de cuatro cifras tiene 10 000 combinaciones:
/// con un hash rápido se rompe al instante, y el coste del KDF es lo único
/// que hace que la fuerza bruta deje de ser gratis.
class AppLockService {
  AppLockService(this._keyManager, {FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ?? const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        ),
        _auth = auth ?? LocalAuthentication();

  final EncryptionKeyManager _keyManager;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  /// `true` si el dispositivo tiene huella, cara o iris configurados.
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final List<BiometricType> types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      // En un emulador sin hardware biométrico el plugin lanza. No es un
      // error de la app: simplemente no hay biometría.
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const <BiometricType>[];
    }
  }

  Future<UnlockResult> authenticateWithBiometrics() async {
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: 'Desbloquea Hannah\'s Wallet',
        // Solo biometría: si se permitiese el patron o el PIN del dispositivo,
        // el bloqueo de la app no añadiría nada sobre el del móvil.
        biometricOnly: true,
        // Aguanta que el sistema mande la app a segundo plano mientras se
        // muestra el dialogo del sensor, en vez de cancelar la peticion.
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.success : UnlockResult.cancelled;
    } catch (_) {
      return UnlockResult.unavailable;
    }
  }

  // ------------------------------------------------------------------ PIN

  Future<bool> hasPin() async {
    final String? stored = await _storage.read(key: AppConstants.kAppPinKey);
    return stored != null && stored.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    if (pin.length < 4) {
      throw const ValidationFailure('El PIN debe tener al menos 4 dígitos.');
    }
    final Uint8List salt =
        EncryptionKeyManager.randomBytes(AppConstants.saltLengthBytes);
    final String hash = await _keyManager.derivePinHash(pin, salt);
    await _storage.write(
      key: AppConstants.kAppPinSaltKey,
      value: base64.encode(salt),
    );
    await _storage.write(key: AppConstants.kAppPinKey, value: hash);
  }

  /// Comprueba el PIN en tiempo constante.
  ///
  /// La comparacion no usa `==` sobre los Strings: `==` sale en cuanto
  /// encuentra el primer byte distinto, y ese tiempo distinto es medible.
  Future<bool> verifyPin(String pin) async {
    final String? storedHash = await _storage.read(key: AppConstants.kAppPinKey);
    final String? storedSalt =
        await _storage.read(key: AppConstants.kAppPinSaltKey);
    if (storedHash == null || storedSalt == null) return false;

    final String candidate = await _keyManager.derivePinHash(
      pin,
      Uint8List.fromList(base64.decode(storedSalt)),
    );
    return _constantTimeEquals(candidate, storedHash);
  }

  Future<void> clearPin() async {
    await _storage.delete(key: AppConstants.kAppPinKey);
    await _storage.delete(key: AppConstants.kAppPinSaltKey);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
