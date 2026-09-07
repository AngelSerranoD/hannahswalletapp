import 'dart:typed_data';

import 'biometric_unlock.dart';

/// Sustituto para plataformas sin WebAuthn (móvil nativo y los tests de VM).
///
/// En móvil el equivalente lo da `local_auth` a través de `LockGate`; aquí solo
/// se declara que no hay nada, para que la UI no ofrezca una opción inexistente.
class UnsupportedBiometricUnlock implements BiometricUnlock {
  const UnsupportedBiometricUnlock();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> supportsPrf() async => false;

  @override
  Future<BiometricStatus> diagnose() async => BiometricStatus.noWebAuthn;

  @override
  Future<BiometricEnrollment> enroll({required String accountLabel}) async {
    throw const BiometricException(BiometricFailure.unsupported);
  }

  @override
  Future<Uint8List> obtainSecret({
    required String credentialId,
    required Uint8List prfSalt,
  }) async {
    throw const BiometricException(BiometricFailure.unsupported);
  }
}

BiometricUnlock createBiometricUnlock() => const UnsupportedBiometricUnlock();
