import 'lock_gate_stub.dart'
    if (dart.library.io) 'lock_gate_io.dart'
    if (dart.library.js_interop) 'lock_gate_web.dart' as impl;

/// Resultado de un intento de desbloqueo biométrico.
enum BiometricResult {
  success,
  failed,

  /// El usuario cerro el dialogo del sistema. No cuenta como fallo.
  cancelled,

  /// El dispositivo no ofrece biometría utilizable.
  unavailable,
}

/// Segunda capa de proteccion: la que cubre la PANTALLA, no el fichero.
///
/// Solo existe de verdad en móvil. En la PWA no hay equivalente: `local_auth`
/// no tiene implementación web, y ahi la proteccion ya la da la contraseña
/// maestra sin la cual la bóveda ni siquiera se puede descifrar.
///
/// La implementación se elige con el mismo import condicional que el backend
/// de datos, para que el bundle web no arrastre `local_auth`.
abstract interface class LockGate {
  /// `true` si esta plataforma puede ofrecer bloqueo propio.
  bool get isSupported;

  Future<bool> isBiometricAvailable();
  Future<BiometricResult> authenticate();

  Future<bool> hasPin();
  Future<void> setPin(String pin);
  Future<bool> verifyPin(String pin);
  Future<void> clearPin();
}

LockGate createLockGate() => impl.createLockGate();
