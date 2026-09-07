import 'dart:typed_data';

import 'biometric_unlock_stub.dart'
    if (dart.library.js_interop) 'biometric_unlock_web.dart' as impl;

/// Credencial biométrica recién creada.
class BiometricEnrollment {
  const BiometricEnrollment({
    required this.credentialId,
    required this.prfSalt,
    required this.prfOutput,
  });

  /// Identificador de la passkey. No es secreto: sirve para pedir ESA
  /// credencial concreta al desbloquear.
  final String credentialId;

  /// Entrada fija del PRF. Tampoco es secreta; lo secreto es la salida, que
  /// solo el autenticador puede calcular tras verificar al usuario.
  final Uint8List prfSalt;

  /// Los 32 bytes que devuelve el PRF. ESTO sí es secreto: de aquí sale la
  /// llave que envuelve la clave de datos.
  final Uint8List prfOutput;
}

/// Por qué la biometría está o no disponible.
///
/// Existe para poder DECIRLE al usuario qué le falta. Un interruptor gris sin
/// explicación es lo peor que se le puede enseñar a alguien que quiere activar
/// Face ID: no sabe si es culpa suya, de su móvil o de la app.
enum BiometricStatus {
  /// Se puede activar.
  ready('Listo para usar'),

  /// La página no se sirve por HTTPS. WebAuthn no existe fuera de un origen
  /// seguro, y es el motivo más habitual al probar la PWA en una IP local.
  insecureContext(
    'Face ID necesita HTTPS. Abre la app por https:// (o en localhost).',
  ),

  /// El navegador no tiene WebAuthn.
  noWebAuthn('Este navegador no admite Face ID.'),

  /// No hay Face ID ni Touch ID configurados en el dispositivo.
  noPlatformAuthenticator(
    'Configura Face ID o Touch ID en el dispositivo para poder usarlo aquí.',
  ),

  /// Hay biometría, pero sin la extensión PRF no sirve para cifrar.
  noPrf(
    'Tu dispositivo permite Face ID, pero no puede proteger la clave con él. '
    'Hace falta iOS 18 o posterior.',
  );

  const BiometricStatus(this.message);

  /// Explicación lista para enseñar en Ajustes.
  final String message;

  bool get isReady => this == BiometricStatus.ready;
}

/// Por qué no se pudo usar la biometría.
enum BiometricFailure {
  /// El navegador o el dispositivo no la soportan.
  unsupported,

  /// El usuario canceló el diálogo del sistema. No es un fallo.
  cancelled,

  /// Hay biometría, pero sin la extensión PRF no sirve para cifrar.
  noPrf,

  /// Cualquier otro fallo del autenticador.
  failed,
}

class BiometricException implements Exception {
  const BiometricException(this.reason, [this.message]);

  final BiometricFailure reason;
  final String? message;

  @override
  String toString() => 'BiometricException($reason, $message)';
}

/// Desbloqueo biométrico de la PWA mediante WebAuthn.
///
/// **Por qué WebAuthn y no un simple "¿eres tú?"**: sin servidor, usar
/// WebAuthn como un login normal no protegería nada — la comprobación pasaría
/// en JavaScript y cualquiera con las herramientas del navegador la saltaría,
/// y los datos seguirían descifrables por otra vía.
///
/// La extensión **PRF** cambia el planteamiento por completo: el autenticador
/// (el Secure Enclave del iPhone) devuelve un secreto de 32 bytes que solo
/// calcula DESPUÉS de verificar la cara o la huella, y que no está guardado en
/// ningún sitio al que el navegador pueda llegar. Ese secreto es el que
/// desenvuelve la clave de datos. Saltarse Face ID no da acceso: deja la
/// bóveda igual de ilegible, porque la llave sencillamente no existe sin él.
///
/// Requiere Safari 18 / iOS 18 o superior. En cualquier otro caso, la app
/// sigue funcionando con la contraseña maestra y no ofrece esta opción.
abstract interface class BiometricUnlock {
  /// `true` si hay un autenticador de plataforma (Face ID / Touch ID).
  Future<bool> isAvailable();

  /// `true` si además soporta la extensión PRF, que es lo que hace falta para
  /// cifrar. Puede haber biometría sin PRF: en ese caso NO se ofrece.
  Future<bool> supportsPrf();

  /// Comprueba TODOS los requisitos y devuelve el primero que falla.
  Future<BiometricStatus> diagnose();

  /// Crea la passkey y obtiene el primer secreto.
  Future<BiometricEnrollment> enroll({required String accountLabel});

  /// Vuelve a obtener el secreto de una credencial ya registrada.
  Future<Uint8List> obtainSecret({
    required String credentialId,
    required Uint8List prfSalt,
  });
}

BiometricUnlock createBiometricUnlock() => impl.createBiometricUnlock();
