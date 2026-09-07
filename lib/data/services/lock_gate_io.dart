import '../security/encryption_key_manager.dart';
import 'app_lock_service.dart';
import 'lock_gate.dart';

/// Bloqueo de pantalla en móvil: biometría del sistema con PIN de respaldo.
///
/// Envuelve al `AppLockService`, que es quien habla con `local_auth` y con el
/// Keystore. Este adaptador existe para que la interfaz comun no dependa de
/// esos paquetes.
class NativeLockGate implements LockGate {
  NativeLockGate() : _service = AppLockService(EncryptionKeyManager());

  final AppLockService _service;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isBiometricAvailable() => _service.isBiometricAvailable();

  @override
  Future<BiometricResult> authenticate() async {
    final UnlockResult result = await _service.authenticateWithBiometrics();
    return switch (result) {
      UnlockResult.success => BiometricResult.success,
      UnlockResult.failed => BiometricResult.failed,
      UnlockResult.cancelled => BiometricResult.cancelled,
      UnlockResult.unavailable => BiometricResult.unavailable,
    };
  }

  @override
  Future<bool> hasPin() => _service.hasPin();

  @override
  Future<void> setPin(String pin) => _service.setPin(pin);

  @override
  Future<bool> verifyPin(String pin) => _service.verifyPin(pin);

  @override
  Future<void> clearPin() => _service.clearPin();
}

LockGate createLockGate() => NativeLockGate();
