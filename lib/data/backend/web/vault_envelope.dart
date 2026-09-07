import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../security/encryption_key_manager.dart';

/// Cómo se desbloquea un sobre.
enum VaultKeySource {
  /// Contraseña maestra que escribe el usuario.
  password('password'),

  /// Face ID / Touch ID mediante WebAuthn con la extensión PRF.
  biometric('webauthn-prf');

  const VaultKeySource(this.tag);
  final String tag;

  static VaultKeySource? fromTag(String tag) {
    for (final VaultKeySource s in values) {
      if (s.tag == tag) return s;
    }
    return null;
  }
}

/// Un sobre: la clave de datos cifrada con UNA de las formas de desbloqueo.
///
/// Este es el patrón de "envelope encryption" que usan los gestores de
/// contraseñas serios, y es lo que permite tener a la vez contraseña maestra y
/// Face ID sin duplicar los datos ni degradar la seguridad de ninguno de los
/// dos: cada sobre guarda LA MISMA clave de datos, cifrada con una llave
/// distinta.
class KeyWrap {
  const KeyWrap({
    required this.source,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    this.salt,
    this.iterations,
    this.credentialId,
    this.prfSalt,
    this.label,
  });

  factory KeyWrap.fromMap(Map<String, Object?> map) {
    Uint8List? decode(Object? value) =>
        value == null ? null : Uint8List.fromList(base64.decode(value as String));

    return KeyWrap(
      source: VaultKeySource.fromTag(map['source']! as String) ??
          VaultKeySource.password,
      nonce: decode(map['nonce'])!,
      ciphertext: decode(map['ciphertext'])!,
      mac: decode(map['mac'])!,
      salt: decode(map['salt']),
      iterations: (map['iterations'] as num?)?.toInt(),
      credentialId: map['credential_id'] as String?,
      prfSalt: decode(map['prf_salt']),
      label: map['label'] as String?,
    );
  }

  final VaultKeySource source;

  /// La clave de datos, cifrada.
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  /// Solo para [VaultKeySource.password].
  final Uint8List? salt;
  final int? iterations;

  /// Solo para [VaultKeySource.biometric]: identifica la passkey y la entrada
  /// del PRF. Ninguno de los dos es secreto.
  final String? credentialId;
  final Uint8List? prfSalt;

  /// Nombre para enseñar en Ajustes ("Face ID de este iPhone").
  final String? label;

  Map<String, Object?> toMap() => <String, Object?>{
        'source': source.tag,
        'nonce': base64.encode(nonce),
        'ciphertext': base64.encode(ciphertext),
        'mac': base64.encode(mac),
        if (salt != null) 'salt': base64.encode(salt!),
        if (iterations != null) 'iterations': iterations,
        if (credentialId != null) 'credential_id': credentialId,
        if (prfSalt != null) 'prf_salt': base64.encode(prfSalt!),
        if (label != null) 'label': label,
      };
}

/// La bóveda completa tal y como se guarda en IndexedDB.
///
/// Formato 2. La versión 1 cifraba los datos DIRECTAMENTE con la clave
/// derivada de la contraseña, lo que tenía dos consecuencias molestas:
/// cambiar la contraseña obligaba a volver a cifrar todo el historial, y no
/// había forma de añadir Face ID sin una segunda copia de los datos.
///
/// Ahora los datos se cifran con una clave de datos aleatoria (DEK) y son los
/// SOBRES los que guardan esa clave, cada uno protegido por una llave
/// distinta. Cambiar la contraseña reescribe 60 bytes en vez de megabytes.
class VaultEnvelope {
  const VaultEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.wraps,
    this.version = currentVersion,
  });

  factory VaultEnvelope.fromMap(Map<String, Object?> map) {
    final int version = (map['version'] as num?)?.toInt() ?? 1;
    if (version > currentVersion) {
      throw const StorageFailure(
        'Los datos de este navegador los escribió una versión más nueva de la '
        'app. Actualízala para poder abrirlos.',
      );
    }

    Uint8List decode(Object? value) =>
        Uint8List.fromList(base64.decode(value! as String));

    // La versión 1 no tenía sobres: los datos iban cifrados directamente con
    // la clave de la contraseña. Se representa como un sobre "degenerado" para
    // que el resto del código no tenga que conocer los dos formatos.
    if (version == 1) {
      return VaultEnvelope(
        version: 1,
        nonce: decode(map['nonce']),
        ciphertext: decode(map['ciphertext']),
        mac: decode(map['mac']),
        wraps: <KeyWrap>[
          KeyWrap(
            source: VaultKeySource.password,
            nonce: Uint8List(0),
            ciphertext: Uint8List(0),
            mac: Uint8List(0),
            salt: decode(map['salt']),
            iterations: (map['iterations'] as num?)?.toInt() ??
                AppConstants.pbkdf2IterationsWeb,
          ),
        ],
      );
    }

    final List<dynamic> rawWraps = map['wraps'] as List<dynamic>? ?? <dynamic>[];
    return VaultEnvelope(
      version: version,
      nonce: decode(map['nonce']),
      ciphertext: decode(map['ciphertext']),
      mac: decode(map['mac']),
      wraps: rawWraps
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> raw) => KeyWrap.fromMap(<String, Object?>{
                for (final MapEntry<dynamic, dynamic> e in raw.entries)
                  e.key.toString(): e.value,
              }))
          .toList(growable: false),
    );
  }

  static const int currentVersion = 2;

  final int version;

  /// Contenido de la bóveda, cifrado con la clave de datos.
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  final List<KeyWrap> wraps;

  bool get isLegacy => version == 1;

  bool has(VaultKeySource source) =>
      wraps.any((KeyWrap w) => w.source == source);

  KeyWrap? wrapFor(VaultKeySource source) {
    for (final KeyWrap w in wraps) {
      if (w.source == source) return w;
    }
    return null;
  }

  VaultEnvelope copyWith({
    Uint8List? nonce,
    Uint8List? ciphertext,
    Uint8List? mac,
    List<KeyWrap>? wraps,
  }) {
    return VaultEnvelope(
      nonce: nonce ?? this.nonce,
      ciphertext: ciphertext ?? this.ciphertext,
      mac: mac ?? this.mac,
      wraps: wraps ?? this.wraps,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'version': currentVersion,
        'nonce': base64.encode(nonce),
        'ciphertext': base64.encode(ciphertext),
        'mac': base64.encode(mac),
        'wraps': wraps.map((KeyWrap w) => w.toMap()).toList(),
      };
}

/// Operaciones criptográficas sobre la bóveda.
///
/// Reglas que se respetan sin excepción:
///
///  * **Un nonce nuevo en cada cifrado.** Repetir el par (clave, nonce) en
///    AES-GCM permite recuperar texto claro sin conocer la clave; es el fallo
///    más fácil de cometer y el más grave.
///  * **La clave de datos jamás se guarda sin cifrar**, ni en IndexedDB ni en
///    ningún otro sitio: solo vive en memoria mientras la sesión está abierta.
///  * **El material biométrico se pasa por HKDF** antes de usarse como llave,
///    con una etiqueta de dominio, para que ese secreto no sirva para nada
///    fuera de esta app aunque se filtrara.
abstract final class VaultCipher {
  static final Cipher _cipher = AesGcm.with256bits();

  /// Etiqueta de dominio del HKDF. Ata la llave derivada a este uso concreto.
  static const String _hkdfInfo = 'hannahs-wallet/vault-key/v2';

  // ------------------------------------------------------------ Creación

  /// Crea una bóveda nueva protegida por contraseña.
  static Future<(VaultEnvelope, SecretKey)> create({
    required String plaintext,
    required String passphrase,
    int iterations = AppConstants.pbkdf2IterationsWeb,
  }) async {
    // La clave de datos es aleatoria y NO deriva de la contraseña: así la
    // contraseña puede cambiar sin tocar los datos.
    final SecretKey dek = SecretKey(
      EncryptionKeyManager.randomBytes(AppConstants.keyLengthBytes),
    );

    final SecretBox body = await _encrypt(plaintext, dek);
    final KeyWrap wrap = await _wrapWithPassword(dek, passphrase, iterations);

    return (
      VaultEnvelope(
        nonce: Uint8List.fromList(body.nonce),
        ciphertext: Uint8List.fromList(body.cipherText),
        mac: Uint8List.fromList(body.mac.bytes),
        wraps: <KeyWrap>[wrap],
      ),
      dek,
    );
  }

  // ---------------------------------------------------------- Apertura

  /// Abre con contraseña. Devuelve `null` si no es correcta.
  ///
  /// Distinguir "contraseña incorrecta" de "fichero corrupto" es posible
  /// gracias a que AES-GCM valida su etiqueta antes de entregar nada.
  static Future<(String, SecretKey)?> openWithPassword(
    VaultEnvelope envelope,
    String passphrase,
  ) async {
    final KeyWrap? wrap = envelope.wrapFor(VaultKeySource.password);
    if (wrap == null) return null;

    final SecretKey kek = await _deriveFromPassword(
      passphrase,
      wrap.salt!,
      wrap.iterations ?? AppConstants.pbkdf2IterationsWeb,
    );

    // Formato 1: la clave de la contraseña ES la clave de datos.
    if (envelope.isLegacy) {
      final String? clear = await _decrypt(envelope, kek);
      return clear == null ? null : (clear, kek);
    }

    final SecretKey? dek = await _unwrap(wrap, kek);
    if (dek == null) return null;

    final String? clear = await _decrypt(envelope, dek);
    if (clear == null) {
      throw const SecurityFailure('La bóveda está dañada.');
    }
    return (clear, dek);
  }

  /// Abre con el secreto que devuelve WebAuthn PRF (Face ID).
  static Future<(String, SecretKey)?> openWithBiometricSecret(
    VaultEnvelope envelope,
    Uint8List prfOutput,
  ) async {
    final KeyWrap? wrap = envelope.wrapFor(VaultKeySource.biometric);
    if (wrap == null) return null;

    final SecretKey kek = await _deriveFromPrf(prfOutput);
    final SecretKey? dek = await _unwrap(wrap, kek);
    if (dek == null) return null;

    final String? clear = await _decrypt(envelope, dek);
    if (clear == null) {
      throw const SecurityFailure('La bóveda está dañada.');
    }
    return (clear, dek);
  }

  // ----------------------------------------------------------- Escritura

  /// Vuelve a cifrar el contenido con la MISMA clave de datos.
  ///
  /// Es la operación del guardado normal: no toca los sobres y no ejecuta
  /// ningún KDF, así que anotar un gasto cuesta un AES y no 310 000
  /// iteraciones de PBKDF2.
  static Future<VaultEnvelope> reseal({
    required VaultEnvelope envelope,
    required SecretKey dek,
    required String plaintext,
  }) async {
    final SecretBox body = await _encrypt(plaintext, dek);
    return envelope.copyWith(
      nonce: Uint8List.fromList(body.nonce),
      ciphertext: Uint8List.fromList(body.cipherText),
      mac: Uint8List.fromList(body.mac.bytes),
    );
  }

  /// Sustituye el sobre de contraseña por otro con una contraseña nueva.
  static Future<VaultEnvelope> rewrapPassword({
    required VaultEnvelope envelope,
    required SecretKey dek,
    required String passphrase,
    int iterations = AppConstants.pbkdf2IterationsWeb,
  }) async {
    final KeyWrap wrap = await _wrapWithPassword(dek, passphrase, iterations);
    return envelope.copyWith(
      wraps: <KeyWrap>[
        wrap,
        ...envelope.wraps.where(
          (KeyWrap w) => w.source != VaultKeySource.password,
        ),
      ],
    );
  }

  /// Añade (o reemplaza) el sobre biométrico.
  static Future<VaultEnvelope> addBiometricWrap({
    required VaultEnvelope envelope,
    required SecretKey dek,
    required Uint8List prfOutput,
    required String credentialId,
    required Uint8List prfSalt,
    String? label,
  }) async {
    final SecretKey kek = await _deriveFromPrf(prfOutput);
    final SecretBox box = await _encrypt(
      base64.encode(await dek.extractBytes()),
      kek,
    );

    final KeyWrap wrap = KeyWrap(
      source: VaultKeySource.biometric,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      credentialId: credentialId,
      prfSalt: prfSalt,
      label: label,
    );

    return envelope.copyWith(
      wraps: <KeyWrap>[
        ...envelope.wraps.where(
          (KeyWrap w) => w.source != VaultKeySource.biometric,
        ),
        wrap,
      ],
    );
  }

  /// Quita un sobre.
  ///
  /// NUNCA deja la bóveda sin ninguno: hacerlo equivaldría a destruir los
  /// datos, porque no quedaría forma de recuperar la clave.
  static VaultEnvelope removeWrap(
    VaultEnvelope envelope,
    VaultKeySource source,
  ) {
    final List<KeyWrap> remaining = envelope.wraps
        .where((KeyWrap w) => w.source != source)
        .toList(growable: false);

    if (remaining.isEmpty) {
      throw const SecurityFailure(
        'No se puede quitar la última forma de abrir la bóveda.',
      );
    }
    return envelope.copyWith(wraps: remaining);
  }

  /// Migra una bóveda del formato 1 al 2 conservando la contraseña.
  static Future<VaultEnvelope> migrateLegacy({
    required VaultEnvelope legacy,
    required String plaintext,
    required String passphrase,
  }) async {
    final (VaultEnvelope migrated, _) = await create(
      plaintext: plaintext,
      passphrase: passphrase,
    );
    return migrated;
  }

  // ------------------------------------------------------------ Internos

  static Future<SecretBox> _encrypt(String plaintext, SecretKey key) {
    return _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: _cipher.newNonce(),
    );
  }

  static Future<String?> _decrypt(VaultEnvelope envelope, SecretKey key) async {
    try {
      final List<int> clear = await _cipher.decrypt(
        SecretBox(
          envelope.ciphertext,
          nonce: envelope.nonce,
          mac: Mac(envelope.mac),
        ),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Future<KeyWrap> _wrapWithPassword(
    SecretKey dek,
    String passphrase,
    int iterations,
  ) async {
    final Uint8List salt =
        EncryptionKeyManager.randomBytes(AppConstants.saltLengthBytes);
    final SecretKey kek =
        await _deriveFromPassword(passphrase, salt, iterations);
    final SecretBox box = await _encrypt(
      base64.encode(await dek.extractBytes()),
      kek,
    );

    return KeyWrap(
      source: VaultKeySource.password,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      salt: salt,
      iterations: iterations,
    );
  }

  static Future<SecretKey?> _unwrap(KeyWrap wrap, SecretKey kek) async {
    try {
      final List<int> clear = await _cipher.decrypt(
        SecretBox(
          wrap.ciphertext,
          nonce: wrap.nonce,
          mac: Mac(wrap.mac),
        ),
        secretKey: kek,
      );
      return SecretKey(base64.decode(utf8.decode(clear)));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Future<SecretKey> _deriveFromPassword(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) {
    final Pbkdf2 kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: AppConstants.keyLengthBytes * 8,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  /// Deriva la llave a partir del secreto de WebAuthn PRF.
  ///
  /// Se usa HKDF y no el secreto tal cual porque el PRF es material en bruto
  /// del autenticador: pasarlo por un KDF con etiqueta de dominio garantiza
  /// que la llave resultante solo vale para esta app y este propósito. No hace
  /// falta un KDF costoso -no hay contraseña que adivinar-, sino uno correcto.
  static Future<SecretKey> _deriveFromPrf(Uint8List prfOutput) {
    final Hkdf kdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: AppConstants.keyLengthBytes,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(prfOutput),
      info: utf8.encode(_hkdfInfo),
    );
  }
}
