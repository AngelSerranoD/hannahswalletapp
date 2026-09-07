import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../../../core/constants/app_constants.dart';
import '../../security/encryption_key_manager.dart';
import 'biometric_unlock.dart';

/// Implementación de [BiometricUnlock] sobre la WebAuthn API del navegador.
///
/// Se habla con JavaScript a través de `dart:js_interop_unsafe` (propiedades
/// por nombre) en lugar de con tipos generados: la extensión PRF es reciente y
/// no está en los bindings tipados, así que construir los objetos a mano es lo
/// único que funciona hoy sin depender de que un paquete se ponga al día.
class WebAuthnBiometricUnlock implements BiometricUnlock {
  const WebAuthnBiometricUnlock();

  /// Longitud del reto. No se verifica contra ningún servidor -no lo hay-,
  /// pero WebAuthn exige uno y debe ser aleatorio.
  static const int _challengeBytes = 32;

  JSObject? get _credentialsApi {
    final JSObject? navigator =
        globalContext.getProperty<JSObject?>('navigator'.toJS);
    return navigator?.getProperty<JSObject?>('credentials'.toJS);
  }

  bool get _hasWebAuthn =>
      globalContext.hasProperty('PublicKeyCredential'.toJS).toDart &&
      _credentialsApi != null;

  /// `true` si la página se sirve por HTTPS (o desde localhost).
  ///
  /// WebAuthn no existe fuera de un origen seguro: `navigator.credentials` es
  /// `undefined` y no hay forma de distinguirlo de "el navegador es viejo".
  /// Se comprueba aparte para poder decirle al usuario que le falta HTTPS, que
  /// es el motivo más habitual al probar la PWA en una IP de la red local.
  bool get _isSecureContext {
    final JSAny? flag = globalContext.getProperty<JSAny?>('isSecureContext'.toJS);
    // Si el navegador no expone la propiedad se asume que sí: no conviene
    // bloquear por una comprobación que puede faltar.
    if (flag == null) return true;
    return flag.isTruthy.toDart;
  }

  @override
  Future<BiometricStatus> diagnose() async {
    if (!_isSecureContext) return BiometricStatus.insecureContext;
    if (!_hasWebAuthn) return BiometricStatus.noWebAuthn;
    if (!await isAvailable()) return BiometricStatus.noPlatformAuthenticator;
    if (!await supportsPrf()) return BiometricStatus.noPrf;
    return BiometricStatus.ready;
  }

  @override
  Future<bool> isAvailable() async {
    if (!_hasWebAuthn) return false;
    try {
      final JSObject pkc =
          globalContext.getProperty<JSObject>('PublicKeyCredential'.toJS);
      if (!pkc
          .hasProperty('isUserVerifyingPlatformAuthenticatorAvailable'.toJS)
          .toDart) {
        return false;
      }
      final JSPromise<JSBoolean> promise = pkc.callMethod<JSPromise<JSBoolean>>(
        'isUserVerifyingPlatformAuthenticatorAvailable'.toJS,
      );
      return (await promise.toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si el navegador conoce la extensión PRF.
  ///
  /// Se pregunta por la lista de extensiones soportadas en lugar de crear una
  /// credencial de prueba: crear una dejaría una passkey basura en el llavero
  /// del usuario cada vez que se abre Ajustes.
  @override
  Future<bool> supportsPrf() async {
    if (!await isAvailable()) return false;
    try {
      final JSObject pkc =
          globalContext.getProperty<JSObject>('PublicKeyCredential'.toJS);
      if (!pkc.hasProperty('getClientCapabilities'.toJS).toDart) {
        // Safari 18 expone `getClientCapabilities`. Si no está, no se puede
        // saber sin registrar: se deja que el usuario lo intente y el propio
        // registro dirá si hay PRF o no.
        return true;
      }
      final JSPromise<JSObject> promise =
          pkc.callMethod<JSPromise<JSObject>>('getClientCapabilities'.toJS);
      final JSObject caps = await promise.toDart;
      final JSAny? prf = caps.getProperty<JSAny?>('extension:prf'.toJS);
      return prf.isTruthy.toDart;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<BiometricEnrollment> enroll({required String accountLabel}) async {
    if (!_hasWebAuthn) {
      throw const BiometricException(BiometricFailure.unsupported);
    }

    final Uint8List prfSalt =
        EncryptionKeyManager.randomBytes(AppConstants.keyLengthBytes);
    final Uint8List userId = EncryptionKeyManager.randomBytes(16);

    // --- Opciones de creación de la passkey ---
    final JSObject rp = JSObject()
      ..setProperty('name'.toJS, AppConstants.appName.toJS);

    final JSObject user = JSObject()
      ..setProperty('id'.toJS, userId.toJS)
      ..setProperty('name'.toJS, accountLabel.toJS)
      ..setProperty('displayName'.toJS, accountLabel.toJS);

    // ES256 y RS256: los dos algoritmos que exige la especificación como
    // mínimo razonable de compatibilidad.
    final JSArray<JSObject> params = <JSObject>[
      JSObject()
        ..setProperty('type'.toJS, 'public-key'.toJS)
        ..setProperty('alg'.toJS, (-7).toJS),
      JSObject()
        ..setProperty('type'.toJS, 'public-key'.toJS)
        ..setProperty('alg'.toJS, (-257).toJS),
    ].toJS;

    final JSObject selection = JSObject()
      // `platform`: solo Face ID / Touch ID de este dispositivo, nunca una
      // llave externa (que además no soporta PRF en iOS).
      ..setProperty('authenticatorAttachment'.toJS, 'platform'.toJS)
      ..setProperty('residentKey'.toJS, 'required'.toJS)
      ..setProperty('requireResidentKey'.toJS, true.toJS)
      // `required`: sin verificación de usuario no hay biometría, y sin
      // biometría esto no protegería nada.
      ..setProperty('userVerification'.toJS, 'required'.toJS);

    final JSObject extensions = JSObject()
      ..setProperty('prf'.toJS, JSObject());

    final JSObject publicKey = JSObject()
      ..setProperty(
        'challenge'.toJS,
        EncryptionKeyManager.randomBytes(_challengeBytes).toJS,
      )
      ..setProperty('rp'.toJS, rp)
      ..setProperty('user'.toJS, user)
      ..setProperty('pubKeyCredParams'.toJS, params)
      ..setProperty('authenticatorSelection'.toJS, selection)
      ..setProperty('timeout'.toJS, 120000.toJS)
      // `none`: no se necesita saber qué fabricante hizo el autenticador, y
      // pedir attestation añade un diálogo extra sin aportar nada aquí.
      ..setProperty('attestation'.toJS, 'none'.toJS)
      ..setProperty('extensions'.toJS, extensions);

    final JSObject options = JSObject()
      ..setProperty('publicKey'.toJS, publicKey);

    final JSObject credential = await _call('create', options);
    final String credentialId = _readCredentialId(credential);

    // El PRF no se evalúa al crear -Safari no lo devuelve en `create`-, así
    // que se pide inmediatamente después con un `get`. Para el usuario es un
    // segundo Face ID seguido, y ocurre una sola vez al activar la opción.
    final Uint8List prfOutput = await obtainSecret(
      credentialId: credentialId,
      prfSalt: prfSalt,
    );

    return BiometricEnrollment(
      credentialId: credentialId,
      prfSalt: prfSalt,
      prfOutput: prfOutput,
    );
  }

  @override
  Future<Uint8List> obtainSecret({
    required String credentialId,
    required Uint8List prfSalt,
  }) async {
    if (!_hasWebAuthn) {
      throw const BiometricException(BiometricFailure.unsupported);
    }

    final JSObject first = JSObject()..setProperty('first'.toJS, prfSalt.toJS);
    final JSObject prf = JSObject()..setProperty('eval'.toJS, first);
    final JSObject extensions = JSObject()..setProperty('prf'.toJS, prf);

    final JSObject descriptor = JSObject()
      ..setProperty('type'.toJS, 'public-key'.toJS)
      ..setProperty('id'.toJS, _decodeId(credentialId).toJS);

    final JSObject publicKey = JSObject()
      ..setProperty(
        'challenge'.toJS,
        EncryptionKeyManager.randomBytes(_challengeBytes).toJS,
      )
      ..setProperty('allowCredentials'.toJS, <JSObject>[descriptor].toJS)
      ..setProperty('userVerification'.toJS, 'required'.toJS)
      ..setProperty('timeout'.toJS, 120000.toJS)
      ..setProperty('extensions'.toJS, extensions);

    final JSObject options = JSObject()
      ..setProperty('publicKey'.toJS, publicKey);

    final JSObject assertion = await _call('get', options);
    return _readPrfResult(assertion);
  }

  /// Llama a `navigator.credentials.<method>` y traduce los errores.
  Future<JSObject> _call(String method, JSObject options) async {
    final JSObject? api = _credentialsApi;
    if (api == null) {
      throw const BiometricException(BiometricFailure.unsupported);
    }

    try {
      final JSPromise<JSAny?> promise =
          api.callMethod<JSPromise<JSAny?>>(method.toJS, options);
      final JSAny? result = await promise.toDart;
      if (result == null) {
        throw const BiometricException(BiometricFailure.cancelled);
      }
      return result as JSObject;
    } on BiometricException {
      rethrow;
    } catch (error) {
      // `NotAllowedError` es lo que devuelve el navegador tanto si el usuario
      // cancela como si agota el tiempo: en ninguno de los dos casos conviene
      // enseñar un error rojo, solo volver a la contraseña.
      final String name = _errorName(error);
      if (name == 'NotAllowedError' || name == 'AbortError') {
        throw const BiometricException(BiometricFailure.cancelled);
      }
      if (name == 'NotSupportedError') {
        throw const BiometricException(BiometricFailure.unsupported);
      }
      throw BiometricException(BiometricFailure.failed, '$error');
    }
  }

  /// Nombre de la excepción del navegador.
  ///
  /// Se lee del texto en lugar de con `error is JSObject`: comprobar tipos de
  /// interop en tiempo de ejecución no se comporta igual al compilar a
  /// JavaScript que a WebAssembly, y aquí solo hace falta distinguir una
  /// cancelación de un fallo real. Un `DOMException` se convierte en
  /// "NotAllowedError: ...", así que el texto basta y es estable.
  static String _errorName(Object error) {
    final String text = error.toString();
    for (final String name in <String>[
      'NotAllowedError',
      'AbortError',
      'NotSupportedError',
      'InvalidStateError',
      'SecurityError',
    ]) {
      if (text.contains(name)) return name;
    }
    return '';
  }

  static String _readCredentialId(JSObject credential) {
    final JSAny? rawId = credential.getProperty<JSAny?>('rawId'.toJS);
    if (rawId == null) {
      throw const BiometricException(
        BiometricFailure.failed,
        'El autenticador no devolvió identificador.',
      );
    }
    return base64Url.encode(_toBytes(rawId));
  }

  /// Saca los 32 bytes del PRF del resultado de las extensiones.
  static Uint8List _readPrfResult(JSObject assertion) {
    final JSObject? results = assertion
        .callMethod<JSObject?>('getClientExtensionResults'.toJS);
    final JSObject? prf = results?.getProperty<JSObject?>('prf'.toJS);
    final JSObject? values = prf?.getProperty<JSObject?>('results'.toJS);
    final JSAny? first = values?.getProperty<JSAny?>('first'.toJS);

    if (first == null) {
      // Hay biometría, pero el autenticador no dio material criptográfico.
      // Sin él no se puede cifrar nada, así que no se ofrece la opción en vez
      // de fingir que funciona.
      throw const BiometricException(BiometricFailure.noPrf);
    }
    return _toBytes(first);
  }

  static Uint8List _toBytes(JSAny value) {
    if (value.instanceOfString('ArrayBuffer')) {
      return (value as JSArrayBuffer).toDart.asUint8List();
    }
    // TypedArray (Uint8Array y compañía): se lee su buffer subyacente.
    final JSAny? buffer = (value as JSObject).getProperty<JSAny?>('buffer'.toJS);
    if (buffer != null && buffer.instanceOfString('ArrayBuffer')) {
      final int offset =
          value.getProperty<JSNumber?>('byteOffset'.toJS)?.toDartInt ?? 0;
      final int length =
          value.getProperty<JSNumber?>('byteLength'.toJS)?.toDartInt ?? 0;
      return (buffer as JSArrayBuffer)
          .toDart
          .asUint8List(offset, length);
    }
    throw const BiometricException(
      BiometricFailure.failed,
      'Formato inesperado del autenticador.',
    );
  }

  static Uint8List _decodeId(String credentialId) =>
      Uint8List.fromList(base64Url.decode(credentialId));
}

BiometricUnlock createBiometricUnlock() => const WebAuthnBiometricUnlock();
