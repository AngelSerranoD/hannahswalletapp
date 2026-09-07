import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/constants/app_constants.dart';
import 'package:hannahswalletapp/core/error/failures.dart';
import 'package:hannahswalletapp/data/backend/app_backend.dart';
import 'package:hannahswalletapp/data/backend/web/biometric_unlock.dart';
import 'package:hannahswalletapp/data/backend/web/vault_envelope.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/data/security/encryption_key_manager.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pruebas de las defensas de la app.
///
/// Cada una corresponde a un fallo concreto que se podría cometer y que no
/// daría ningún síntoma visible: una contraseña que se puede probar sin
/// límite, un nonce repetido, una bóveda que se queda sin forma de abrirse.
/// Son justo los errores que no aparecen usando la app, solo cuando alguien
/// va a por los datos.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));

  const String pass = 'contrasena-larga-1';

  /// El almacén en memoria de idb_shim es único por proceso, así que sin este
  /// borrado las bóvedas de una prueba se colarían en la siguiente.
  setUp(() async => VaultStore(factory: idbFactoryMemory).delete());

  WebBackend makeBackend({BiometricUnlock? biometrics}) => WebBackend(
        store: VaultStore(factory: idbFactoryMemory),
        biometrics: biometrics,
      );

  group('cifrado de sobres', () {
    test('cambiar la contraseña NO vuelve a cifrar los datos', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend = WebBackend(store: store);
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.flush();

      final VaultEnvelope before = (await store.read())!;
      await backend.changePassphrase(pass, 'otra-contrasena-larga');
      final VaultEnvelope after = (await store.read())!;

      // El cuerpo cifrado es idéntico: solo se ha reescrito el sobre. Con el
      // diseño anterior habría cambiado entero, y en una bóveda de megabytes
      // eso significa reescribirlo todo por cambiar una contraseña.
      expect(after.ciphertext, equals(before.ciphertext));
      expect(after.nonce, equals(before.nonce));

      final KeyWrap oldWrap = before.wrapFor(VaultKeySource.password)!;
      final KeyWrap newWrap = after.wrapFor(VaultKeySource.password)!;
      expect(newWrap.ciphertext, isNot(equals(oldWrap.ciphertext)));
      // Salt nuevo: reutilizarlo ataría la clave nueva al material del viejo.
      expect(newWrap.salt, isNot(equals(oldWrap.salt)));
    });

    test('cada guardado usa un nonce distinto', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend = WebBackend(store: store);
      await backend.initialize();
      await backend.create(passphrase: pass);

      final Set<String> nonces = <String>{};
      for (int i = 0; i < 5; i++) {
        await backend.settings.set('nota_$i', 'valor $i');
        await backend.flush();
        nonces.add(base64.encode((await store.read())!.nonce));
      }

      // Repetir el par (clave, nonce) en AES-GCM permite recuperar texto claro
      // sin conocer la clave. Es el error más fácil de cometer al reutilizar
      // una clave entre guardados, que es exactamente lo que hace esta app.
      expect(nonces.length, 5);
    });

    test('no se puede quitar el último sobre', () async {
      final WebBackend backend = makeBackend();
      await backend.initialize();
      await backend.create(passphrase: pass);

      // Quitar la única forma de abrir la bóveda equivaldría a destruir los
      // datos sin avisar.
      expect(
        backend.disableBiometricUnlock,
        returnsNormally,
      );
      final VaultEnvelope envelope =
          (await VaultStore(factory: idbFactoryMemory).read())!;
      expect(envelope.wraps.length, 1);
    });
  });

  group('migración desde el formato 1', () {
    test('una bóveda antigua se abre y se migra sola', () async {
      // Se fabrica a mano una bóveda del formato viejo: los datos cifrados
      // DIRECTAMENTE con la clave derivada de la contraseña, sin sobres.
      const String payload = '{"wallets":[],"categories":[],"transactions":[],'
          '"budgets":[],"recurring_rules":[],"app_settings":[]}';

      final Uint8List salt =
          EncryptionKeyManager.randomBytes(AppConstants.saltLengthBytes);
      final SecretKey key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: AppConstants.pbkdf2IterationsWeb,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);

      final AesGcm cipher = AesGcm.with256bits();
      final SecretBox box = await cipher.encrypt(
        utf8.encode(payload),
        secretKey: key,
        nonce: cipher.newNonce(),
      );

      await _writeRaw(<String, Object?>{
        'version': 1,
        'iterations': AppConstants.pbkdf2IterationsWeb,
        'salt': base64.encode(salt),
        'nonce': base64.encode(box.nonce),
        'ciphertext': base64.encode(box.cipherText),
        'mac': base64.encode(box.mac.bytes),
      });

      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend = WebBackend(store: store);

      expect(await backend.initialize(), BackendStatus.locked);
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);

      // Ya en formato 2: a partir de ahora admite Face ID y cambios de
      // contraseña baratos.
      final VaultEnvelope migrated = (await store.read())!;
      expect(migrated.version, VaultEnvelope.currentVersion);
      expect(migrated.isLegacy, isFalse);
      expect(migrated.has(VaultKeySource.password), isTrue);

      // Y la contraseña de siempre sigue valiendo.
      await backend.lock();
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
    });

    test('rechaza un formato del futuro en vez de romper los datos', () async {
      await _writeRaw(<String, Object?>{
        'version': 99,
        'nonce': base64.encode(Uint8List(12)),
        'ciphertext': base64.encode(Uint8List(4)),
        'mac': base64.encode(Uint8List(16)),
        'wraps': <dynamic>[],
      });

      expect(
        () => VaultStore(factory: idbFactoryMemory).read(),
        throwsA(isA<StorageFailure>()),
      );
    });
  });

  group('límite de intentos', () {
    test('penaliza tras varios fallos seguidos', () async {
      final WebBackend backend = makeBackend();
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.lock();

      // Los primeros errores no penalizan: teclear mal es normal.
      for (int i = 0; i < AppConstants.maxFreeAttempts; i++) {
        expect(
          await backend.unlock(passphrase: 'incorrecta-$i'),
          UnlockOutcome.wrongPassphrase,
        );
        expect(await backend.lockoutRemaining(), Duration.zero);
      }

      // El siguiente ya cuesta espera.
      expect(
        await backend.unlock(passphrase: 'incorrecta-x'),
        UnlockOutcome.wrongPassphrase,
      );
      expect(await backend.lockoutRemaining(), greaterThan(Duration.zero));

      // Y mientras dura, ni siquiera la contraseña BUENA abre: si no, bastaría
      // con seguir probando y el límite no serviría de nada.
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.lockedOut);
    });

    test('la espera crece con cada fallo', () async {
      final WebBackend backend = makeBackend();
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.lock();

      for (int i = 0; i <= AppConstants.maxFreeAttempts; i++) {
        await backend.unlock(passphrase: 'mal-$i');
      }
      final Duration first = await backend.lockoutRemaining();

      // Se fuerza otro fallo saltándose la espera, escribiendo el contador a
      // mano: probar el retroceso esperando de verdad tardaría minutos.
      await VaultStore(factory: idbFactoryMemory).writeAttempts(
        const AttemptRecord(failures: AppConstants.maxFreeAttempts + 3),
      );
      await backend.unlock(passphrase: 'mal-otra-vez');
      final Duration later = await backend.lockoutRemaining();

      expect(later, greaterThan(first));
      // Con tope, para no dejar al usuario fuera media hora por equivocarse.
      expect(later, lessThanOrEqualTo(AppConstants.maxLockout));
    });

    test('acertar borra el contador', () async {
      final WebBackend backend = makeBackend();
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.lock();

      await backend.unlock(passphrase: 'mal');
      await backend.unlock(passphrase: 'mal');
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);

      final AttemptRecord record =
          await VaultStore(factory: idbFactoryMemory).readAttempts();
      expect(record.failures, 0);
    });
  });

  group('desbloqueo biométrico', () {
    test('no se ofrece si el dispositivo no lo soporta', () async {
      final WebBackend backend =
          makeBackend(biometrics: _FakeBiometrics(available: false));
      await backend.initialize();
      await backend.create(passphrase: pass);

      expect(await backend.supportsBiometricUnlock(), isFalse);
      expect(backend.hasBiometricUnlock, isFalse);
    });

    test('hay biometría pero sin PRF: tampoco se ofrece', () async {
      // Face ID que autentica pero no entrega material criptográfico solo
      // sirve para enseñar un diálogo. Ofrecerlo como "protección" sería
      // mentir: los datos seguirían dependiendo únicamente de la contraseña.
      final WebBackend backend = makeBackend(
        biometrics: _FakeBiometrics(prf: false),
      );
      await backend.initialize();
      await backend.create(passphrase: pass);

      expect(await backend.supportsBiometricUnlock(), isFalse);
    });

    test('activarla añade un segundo sobre y abre sin contraseña', () async {
      final _FakeBiometrics fake = _FakeBiometrics();
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend = WebBackend(store: store, biometrics: fake);

      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.settings.set('moneda_test', 'EUR');
      await backend.flush();

      await backend.enableBiometricUnlock();
      expect(backend.hasBiometricUnlock, isTrue);

      final VaultEnvelope envelope = (await store.read())!;
      expect(envelope.wraps.length, 2);
      // Los dos sobres guardan la MISMA clave, no dos copias de los datos.
      expect(envelope.has(VaultKeySource.password), isTrue);
      expect(envelope.has(VaultKeySource.biometric), isTrue);

      await backend.lock();
      expect(await backend.unlockWithBiometrics(), UnlockOutcome.success);
      expect(await backend.settings.get('moneda_test'), 'EUR');

      // Y la contraseña sigue funcionando: la biometría se suma, no sustituye.
      await backend.lock();
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
    });

    test('un secreto biométrico falso no abre la bóveda', () async {
      final _FakeBiometrics fake = _FakeBiometrics();
      final WebBackend backend = makeBackend(biometrics: fake);
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.enableBiometricUnlock();
      await backend.lock();

      // Simula a alguien que consigue provocar la llamada pero no tiene el
      // Secure Enclave: el PRF que llega es otro.
      fake.corruptSecret = true;
      expect(await backend.unlockWithBiometrics(), UnlockOutcome.unavailable);
      expect(backend.status, BackendStatus.locked);

      // La contraseña sigue abriendo, así que no se ha estropeado nada.
      fake.corruptSecret = false;
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
    });

    test('cancelar Face ID no cuenta como fallo', () async {
      final _FakeBiometrics fake = _FakeBiometrics();
      final WebBackend backend = makeBackend(biometrics: fake);
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.enableBiometricUnlock();
      await backend.lock();

      fake.cancel = true;
      expect(await backend.unlockWithBiometrics(), UnlockOutcome.cancelled);

      // Cancelar no debe gastar intentos: no es un ataque, es alguien que
      // prefiere escribir la contraseña.
      expect(await backend.lockoutRemaining(), Duration.zero);
    });

    test('el diagnostico dice el motivo exacto', () async {
      // Un interruptor gris sin explicacion no sirve de nada: la app tiene que
      // poder decir SI es que falta HTTPS, si el movil no tiene Face ID o si
      // lo tiene pero sin PRF.
      final WebBackend sinBiometria =
          makeBackend(biometrics: _FakeBiometrics(available: false));
      expect(await sinBiometria.diagnoseBiometrics(),
          BiometricStatus.noPlatformAuthenticator);

      final WebBackend sinPrf = makeBackend(
        biometrics: _FakeBiometrics(prf: false),
      );
      expect(await sinPrf.diagnoseBiometrics(), BiometricStatus.noPrf);

      final WebBackend listo = makeBackend(biometrics: _FakeBiometrics());
      expect(await listo.diagnoseBiometrics(), BiometricStatus.ready);
      expect(BiometricStatus.ready.isReady, isTrue);

      // Cada motivo trae un mensaje que se puede enseñar tal cual.
      for (final BiometricStatus s in BiometricStatus.values) {
        expect(s.message, isNotEmpty);
      }
    });

    test('quitarla deja solo la contraseña', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend =
          WebBackend(store: store, biometrics: _FakeBiometrics());
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.enableBiometricUnlock();

      await backend.disableBiometricUnlock();
      expect(backend.hasBiometricUnlock, isFalse);
      expect((await store.read())!.wraps.length, 1);

      await backend.lock();
      expect(await backend.unlockWithBiometrics(), UnlockOutcome.unavailable);
      expect(await backend.unlock(passphrase: pass), UnlockOutcome.success);
    });
  });

  group('borrado', () {
    test('wipe se lleva también el contador de intentos', () async {
      final VaultStore store = VaultStore(factory: idbFactoryMemory);
      final WebBackend backend = WebBackend(store: store);
      await backend.initialize();
      await backend.create(passphrase: pass);
      await backend.lock();
      await backend.unlock(passphrase: 'mal');

      await backend.wipe();
      expect((await store.readAttempts()).failures, 0);
      expect(await store.read(), isNull);
    });
  });
}

/// Escribe un registro crudo en el almacén, saltándose `VaultEnvelope`.
///
/// Hace falta para fabricar bóvedas de formatos que la app ya no escribe.
Future<void> _writeRaw(Map<String, Object?> record) async {
  final Database db = await idbFactoryMemory.open(
    AppConstants.webVaultDbName,
    version: 1,
    onUpgradeNeeded: (VersionChangeEvent event) {
      final Database db = event.database;
      if (!db.objectStoreNames.contains(AppConstants.webVaultStoreName)) {
        db.createObjectStore(AppConstants.webVaultStoreName);
      }
    },
  );
  final Transaction txn = db.transaction(
    AppConstants.webVaultStoreName,
    idbModeReadWrite,
  );
  await txn
      .objectStore(AppConstants.webVaultStoreName)
      .put(record, AppConstants.webVaultRecordKey);
  await txn.completed;
  db.close();
}

/// Doble de Face ID.
///
/// Reproduce el contrato del autenticador real: devuelve un secreto DERIVADO
/// del salt, de forma que un salt distinto produce otro secreto, igual que
/// haría el Secure Enclave.
class _FakeBiometrics implements BiometricUnlock {
  _FakeBiometrics({this.available = true, this.prf = true});

  final bool available;
  final bool prf;

  /// Simula que el autenticador devuelve un secreto que no corresponde.
  bool corruptSecret = false;

  /// Simula que el usuario cierra el diálogo del sistema.
  bool cancel = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> supportsPrf() async => prf;

  @override
  Future<BiometricStatus> diagnose() async {
    if (!available) return BiometricStatus.noPlatformAuthenticator;
    if (!prf) return BiometricStatus.noPrf;
    return BiometricStatus.ready;
  }

  @override
  Future<BiometricEnrollment> enroll({required String accountLabel}) async {
    if (!available) {
      throw const BiometricException(BiometricFailure.unsupported);
    }
    if (!prf) throw const BiometricException(BiometricFailure.noPrf);

    final Uint8List salt = EncryptionKeyManager.randomBytes(32);
    return BiometricEnrollment(
      credentialId: 'credencial-de-prueba',
      prfSalt: salt,
      prfOutput: _secretFor(salt),
    );
  }

  @override
  Future<Uint8List> obtainSecret({
    required String credentialId,
    required Uint8List prfSalt,
  }) async {
    if (cancel) throw const BiometricException(BiometricFailure.cancelled);
    if (!available) {
      throw const BiometricException(BiometricFailure.unsupported);
    }
    if (corruptSecret) return Uint8List(32);
    return _secretFor(prfSalt);
  }

  /// Función determinista: mismo salt, mismo secreto.
  static Uint8List _secretFor(Uint8List salt) {
    final Uint8List out = Uint8List(32);
    for (int i = 0; i < out.length; i++) {
      out[i] = (salt[i % salt.length] ^ 0x5A) & 0xFF;
    }
    return out;
  }
}
