import 'lock_gate.dart';

/// Bloqueo de pantalla en la PWA: no existe, y es correcto que no exista.
///
/// En el navegador no hay `local_auth` ni un almacen protegido por hardware
/// donde guardar un PIN. Añadir aquí un PIN comprobado en JavaScript sería
/// seguridad de atrezo: cualquiera con las herramientas de desarrollo lo
/// saltaría, y además los datos ya están cifrados con la contraseña maestra,
/// que es lo que de verdad los protege.
class WebLockGate implements LockGate {
  const WebLockGate();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isBiometricAvailable() async => false;

  @override
  Future<BiometricResult> authenticate() async => BiometricResult.unavailable;

  @override
  Future<bool> hasPin() async => false;

  @override
  Future<void> setPin(String pin) async {}

  @override
  Future<bool> verifyPin(String pin) async => false;

  @override
  Future<void> clearPin() async {}
}

LockGate createLockGate() => const WebLockGate();
