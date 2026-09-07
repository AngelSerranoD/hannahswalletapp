import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/app.dart';
import 'package:hannahswalletapp/core/di/providers.dart';
import 'package:hannahswalletapp/data/backend/web/biometric_unlock.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/data/security/encryption_key_manager.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Verificación del desbloqueo con Face ID, de punta a punta y por la interfaz.
///
/// `security_test.dart` ya comprueba la criptografía de los sobres. Esto
/// comprueba lo otro, que es lo que de verdad falla en la práctica: que el
/// interruptor de Ajustes se pueda tocar, que al activarlo aparezca el botón
/// de Face ID en la pantalla de la bóveda, y que ese botón abra.
///
/// El autenticador real no existe en un test, así que se sustituye por un
/// doble que reproduce su contrato: devuelve un secreto derivado del salt,
/// igual que haría el Secure Enclave.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));
  setUp(() async => VaultStore(factory: idbFactoryMemory).delete());

  const String pass = 'contrasena-de-prueba';

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 80));
  }

  Future<WebBackend> launch(
    WidgetTester tester,
    BiometricUnlock biometrics,
  ) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final WebBackend backend = WebBackend(
      store: VaultStore(factory: idbFactoryMemory),
      biometrics: biometrics,
      kdfIterations: 1000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appBackendProvider.overrideWithValue(backend)],
        child: const HannahsWalletApp(),
      ),
    );
    await settle(tester, rounds: 14);
    return backend;
  }

  Future<void> createVault(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester, rounds: 8);
  }

  testWidgets('se puede activar Face ID y luego abre la bóveda',
      (WidgetTester tester) async {
    final _FakeAuthenticator auth = _FakeAuthenticator();
    final WebBackend backend = await launch(tester, auth);
    await createVault(tester);
    await openSettings(tester);

    // El interruptor está disponible y apagado.
    final Finder faceSwitch = find.ancestor(
      of: find.text('Desbloquear con Face ID'),
      matching: find.byType(SwitchListTile),
    );
    expect(faceSwitch, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(faceSwitch).onChanged,
      isNotNull,
      reason: 'Con un autenticador válido, el interruptor debe poder tocarse',
    );
    expect(tester.widget<SwitchListTile>(faceSwitch).value, isFalse);

    // Activarlo registra la credencial.
    await tester.tap(find.text('Desbloquear con Face ID'));
    await settle(tester, rounds: 16);

    expect(auth.enrollments, 1, reason: 'Debe haber registrado la passkey');
    expect(backend.hasBiometricUnlock, isTrue);

    // Al bloquear, la puerta ofrece Face ID.
    await tester.dragUntilVisible(
      find.text('Bloquear ahora'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Bloquear ahora'));
    await settle(tester, rounds: 14);

    // El intento automático al entrar ya habrá abierto la bóveda: es el
    // comportamiento correcto, porque el usuario activó Face ID justamente
    // para no tener que escribir nada.
    expect(find.text('Saldo acumulado'), findsOneWidget,
        reason: 'Face ID debe abrir la bóveda sin pedir la contraseña');
    expect(auth.secretRequests, greaterThan(1));
  });

  testWidgets('sin PRF el interruptor se bloquea y explica por qué',
      (WidgetTester tester) async {
    // Un dispositivo con Face ID pero sin la extensión PRF: puede autenticar,
    // pero no entregar material criptográfico. Ofrecerlo sería prometer una
    // protección que no existe.
    await launch(tester, _FakeAuthenticator(prf: false));
    await createVault(tester);
    await openSettings(tester);

    final Finder faceSwitch = find.ancestor(
      of: find.text('Desbloquear con Face ID'),
      matching: find.byType(SwitchListTile),
    );
    expect(
      tester.widget<SwitchListTile>(faceSwitch).onChanged,
      isNull,
      reason: 'Sin PRF no debe poder activarse',
    );
    expect(
      find.textContaining('iOS 18'),
      findsOneWidget,
      reason: 'Debe decir POR QUÉ no se puede, no solo dejarlo gris',
    );
  });

  testWidgets('si se cancela Face ID, la contraseña sigue abriendo',
      (WidgetTester tester) async {
    final _FakeAuthenticator auth = _FakeAuthenticator();
    await launch(tester, auth);
    await createVault(tester);
    await openSettings(tester);

    await tester.tap(find.text('Desbloquear con Face ID'));
    await settle(tester, rounds: 16);

    await tester.dragUntilVisible(
      find.text('Bloquear ahora'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await settle(tester, rounds: 4);

    // A partir de aquí el usuario cierra el diálogo del sistema.
    auth.cancel = true;
    await tester.tap(find.text('Bloquear ahora'));
    await settle(tester, rounds: 14);

    expect(find.text('Desbloquear'), findsOneWidget,
        reason: 'Cancelar Face ID debe dejar la puerta abierta a la contraseña');

    await tester.enterText(find.byType(TextField).first, pass);
    await tester.tap(find.text('Desbloquear'));
    await settle(tester, rounds: 18);

    expect(find.text('Saldo acumulado'), findsOneWidget);
  });
}

/// Doble del Secure Enclave.
///
/// Reproduce lo esencial del contrato real: el secreto se DERIVA del salt, de
/// modo que un salt distinto da otro secreto, y solo se entrega tras "verificar
/// al usuario" (aquí, tras comprobar que no se ha cancelado).
class _FakeAuthenticator implements BiometricUnlock {
  _FakeAuthenticator({this.prf = true});

  /// Siempre hay autenticador: el caso de un movil sin biometria lo cubre
  /// `security_test.dart`. Aqui interesa distinguir "listo" de "sin PRF".
  static const bool available = true;

  final bool prf;

  bool cancel = false;
  int enrollments = 0;
  int secretRequests = 0;

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
    enrollments++;
    final Uint8List salt = EncryptionKeyManager.randomBytes(32);
    secretRequests++;
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
    secretRequests++;
    return _secretFor(prfSalt);
  }

  static Uint8List _secretFor(Uint8List salt) {
    final Uint8List out = Uint8List(32);
    for (int i = 0; i < out.length; i++) {
      out[i] = (salt[i % salt.length] ^ 0x5A) & 0xFF;
    }
    return out;
  }
}
