import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/data_change_bus.dart';
import 'app_backend.dart';
import 'web/biometric_unlock.dart';
import 'web/vault_data.dart';
import 'web/vault_envelope.dart';
import 'web/vault_repositories.dart';
import 'web/vault_store.dart';

/// Backend de la PWA: bóveda cifrada sobre IndexedDB.
///
/// Diferencia esencial con el backend nativo: aquí NO hay cifrado invisible.
/// En el móvil la clave sale del Keystore y el usuario no escribe nada; en el
/// navegador no existe ese almacén protegido por hardware, así que la clave se
/// deriva de algo que el usuario aporta: su contraseña maestra o, si el
/// dispositivo lo permite, Face ID a través de WebAuthn PRF.
///
/// La consecuencia, que la interfaz deja muy clara: **si se pierden todas las
/// formas de abrirla, los datos se pierden**. No hay recuperación posible
/// porque no hay ningún sitio donde esté guardada la clave.
class WebBackend implements AppBackend {
  WebBackend({
    VaultStore? store,
    DataChangeBus? bus,
    BiometricUnlock? biometrics,
    int? kdfIterations,
  })  : _store = store ?? VaultStore(),
        _bus = bus ?? DataChangeBus(),
        _biometrics = biometrics ?? createBiometricUnlock(),
        _kdfIterations = kdfIterations ?? AppConstants.pbkdf2IterationsWeb;

  final VaultStore _store;
  final DataChangeBus _bus;
  final BiometricUnlock _biometrics;

  /// Coste del KDF al crear sobres nuevos.
  ///
  /// Cada sobre guarda las iteraciones con las que se hizo, así que este valor
  /// puede subir en el futuro sin dejar inservibles las bóvedas existentes:
  /// se abren con su coste original y se reescriben con el nuevo. Las pruebas
  /// lo bajan para no gastar minutos derivando claves.
  final int _kdfIterations;

  BackendStatus _status = BackendStatus.needsSetup;
  VaultSession? _session;

  /// La bóveda tal y como está en disco. Se conserva para poder reescribir
  /// solo lo que cambia (contenido o sobres) sin releer.
  VaultEnvelope? _envelope;

  /// Clave de datos, viva solo mientras la sesión está abierta.
  ///
  /// Al bloquear se descarta: es lo que hace que "bloquear" signifique algo,
  /// porque sin ella el blob de IndexedDB vuelve a ser ilegible incluso para
  /// el propio proceso.
  SecretKey? _dek;

  @override
  DataChangeBus get changeBus => _bus;

  @override
  String get displayName => 'Bóveda cifrada del navegador';

  @override
  bool get requiresPassphrase => true;

  @override
  BackendStatus get status => _status;

  @override
  bool get hasBiometricUnlock =>
      _envelope?.has(VaultKeySource.biometric) ?? false;

  @override
  Future<BackendStatus> initialize() async {
    _envelope = await _store.read();
    _status =
        _envelope == null ? BackendStatus.needsSetup : BackendStatus.locked;
    return _status;
  }

  @override
  Future<void> create({String? passphrase}) async {
    final String pass = passphrase ?? '';
    _requireStrongEnough(pass);

    final VaultData data = VaultData.seeded();
    final (VaultEnvelope envelope, SecretKey dek) = await VaultCipher.create(
      plaintext: jsonEncode(data.toBackupMap()),
      passphrase: pass,
      iterations: _kdfIterations,
    );

    await _store.write(envelope);
    await _store.writeAttempts(const AttemptRecord());

    _envelope = envelope;
    _dek = dek;
    _openSession(data);
    _status = BackendStatus.ready;
  }

  // --------------------------------------------------------- Desbloqueo

  @override
  Future<Duration> lockoutRemaining() async =>
      (await _store.readAttempts()).remaining;

  @override
  Future<UnlockOutcome> unlock({String? passphrase}) async {
    final VaultEnvelope? envelope = _envelope ?? await _store.read();
    if (envelope == null) {
      _status = BackendStatus.needsSetup;
      return UnlockOutcome.unavailable;
    }
    _envelope = envelope;

    // La penalización se comprueba ANTES de derivar: si no, cada intento
    // bloqueado seguiría costando 310 000 iteraciones de PBKDF2 y el propio
    // rate limiting se convertiría en un modo de agotar la batería.
    final AttemptRecord attempts = await _store.readAttempts();
    if (attempts.isLocked) return UnlockOutcome.lockedOut;

    final (String, SecretKey)? opened =
        await VaultCipher.openWithPassword(envelope, passphrase ?? '');

    if (opened == null) {
      await _registerFailure(attempts);
      return UnlockOutcome.wrongPassphrase;
    }

    await _store.writeAttempts(const AttemptRecord());
    await _adoptSession(opened.$1, opened.$2, envelope, passphrase);
    return UnlockOutcome.success;
  }

  @override
  Future<UnlockOutcome> unlockWithBiometrics() async {
    final VaultEnvelope? envelope = _envelope ?? await _store.read();
    final KeyWrap? wrap = envelope?.wrapFor(VaultKeySource.biometric);
    if (envelope == null || wrap == null) return UnlockOutcome.unavailable;

    try {
      final Uint8List secret = await _biometrics.obtainSecret(
        credentialId: wrap.credentialId!,
        prfSalt: wrap.prfSalt!,
      );
      final (String, SecretKey)? opened =
          await VaultCipher.openWithBiometricSecret(envelope, secret);

      // Un PRF que no abre la bóveda significa que la credencial ya no
      // corresponde a estos datos (por ejemplo, se restauró un backup). No es
      // un fallo de autenticación del usuario.
      if (opened == null) return UnlockOutcome.unavailable;

      _envelope = envelope;
      await _adoptSession(opened.$1, opened.$2, envelope, null);
      return UnlockOutcome.success;
    } on BiometricException catch (error) {
      return switch (error.reason) {
        BiometricFailure.cancelled => UnlockOutcome.cancelled,
        BiometricFailure.unsupported ||
        BiometricFailure.noPrf =>
          UnlockOutcome.unavailable,
        BiometricFailure.failed => UnlockOutcome.unavailable,
      };
    }
  }

  /// Anota el fallo y calcula la espera con retroceso exponencial.
  ///
  /// Los primeros errores no penalizan -teclear mal la contraseña es normal-,
  /// y a partir de ahí la espera se duplica hasta el tope. Con eso, probar el
  /// diccionario entero deja de ser viable aunque alguien se lleve el blob.
  Future<void> _registerFailure(AttemptRecord current) async {
    final int failures = current.failures + 1;
    DateTime? until;

    if (failures > AppConstants.maxFreeAttempts) {
      final int step = failures - AppConstants.maxFreeAttempts;
      final int seconds = min(
        AppConstants.maxLockout.inSeconds,
        5 * pow(2, step - 1).toInt(),
      );
      until = DateTime.now().add(Duration(seconds: seconds));
    }

    await _store.writeAttempts(
      AttemptRecord(failures: failures, lockedUntil: until),
    );
  }

  /// Deja la sesión lista, migrando el formato si hace falta.
  Future<void> _adoptSession(
    String plaintext,
    SecretKey key,
    VaultEnvelope envelope,
    String? passphrase,
  ) async {
    VaultEnvelope current = envelope;
    SecretKey dek = key;

    // Bóveda del formato 1: los datos iban cifrados directamente con la clave
    // de la contraseña. Se migra en cuanto se abre, de forma transparente,
    // para que a partir de ahora se le puedan añadir sobres (Face ID) y
    // cambiar la contraseña sin reescribir el historial.
    if (envelope.isLegacy && passphrase != null) {
      final (VaultEnvelope migrated, SecretKey freshDek) =
          await VaultCipher.create(
        plaintext: plaintext,
        passphrase: passphrase,
        iterations: _kdfIterations,
      );
      await _store.write(migrated);
      current = migrated;
      dek = freshDek;
    }

    final Object? decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) {
      throw const StorageFailure('La bóveda está dañada.');
    }

    _envelope = current;
    _dek = dek;
    _openSession(VaultData.fromBackupMap(decoded));
    _status = BackendStatus.ready;
  }

  // --------------------------------------------------------- Biometría

  @override
  Future<BiometricStatus> diagnoseBiometrics() => _biometrics.diagnose();

  @override
  Future<bool> supportsBiometricUnlock() async {
    if (!await _biometrics.isAvailable()) return false;
    return _biometrics.supportsPrf();
  }

  @override
  Future<void> enableBiometricUnlock() async {
    final SecretKey? dek = _dek;
    final VaultEnvelope? envelope = _envelope;
    if (dek == null || envelope == null) {
      throw const SecurityFailure(
        'Abre la bóveda antes de activar el desbloqueo biométrico.',
      );
    }

    final BiometricEnrollment enrollment =
        await _biometrics.enroll(accountLabel: AppConstants.appName);

    final VaultEnvelope updated = await VaultCipher.addBiometricWrap(
      envelope: envelope,
      dek: dek,
      prfOutput: enrollment.prfOutput,
      credentialId: enrollment.credentialId,
      prfSalt: enrollment.prfSalt,
      label: 'Face ID / Touch ID de este dispositivo',
    );

    await _store.write(updated);
    _envelope = updated;
  }

  @override
  Future<void> disableBiometricUnlock() async {
    final VaultEnvelope? envelope = _envelope;
    if (envelope == null) return;

    final VaultEnvelope updated =
        VaultCipher.removeWrap(envelope, VaultKeySource.biometric);
    await _store.write(updated);
    _envelope = updated;
  }

  // ------------------------------------------------------------ Sesión

  @override
  Future<void> lock() async {
    await flush();
    _session?.dispose();
    _session = null;
    _dek = null;
    _status = BackendStatus.locked;
  }

  @override
  Future<void> wipe() async {
    _session?.dispose();
    _session = null;
    _dek = null;
    _envelope = null;
    await _store.delete();
    _status = BackendStatus.needsSetup;
  }

  @override
  Future<void> flush() async => _session?.flush();

  /// Cambia la contraseña maestra.
  ///
  /// Con el formato de sobres esto reescribe unas decenas de bytes: la clave
  /// de datos no cambia, solo la llave que la envuelve. Antes obligaba a
  /// volver a cifrar el historial entero.
  @override
  Future<void> changePassphrase(String current, String next) async {
    _requireStrongEnough(next);

    final VaultEnvelope? envelope = _envelope ?? await _store.read();
    if (envelope == null) {
      throw const StorageFailure('No hay bóveda que cambiar.');
    }

    final (String, SecretKey)? opened =
        await VaultCipher.openWithPassword(envelope, current);
    if (opened == null) {
      throw const AuthFailure('La contraseña actual no es correcta.');
    }

    final VaultEnvelope updated = await VaultCipher.rewrapPassword(
      envelope: envelope,
      dek: opened.$2,
      passphrase: next,
      iterations: _kdfIterations,
    );
    await _store.write(updated);
    _envelope = updated;
  }

  void _requireStrongEnough(String passphrase) {
    if (passphrase.length < AppConstants.minPassphraseLength) {
      throw const ValidationFailure(
        'La contraseña debe tener al menos '
        '${AppConstants.minPassphraseLength} caracteres.',
      );
    }
  }

  void _openSession(VaultData data) {
    _session?.dispose();
    _session = VaultSession(data: data, bus: _bus, persist: _persist);
  }

  Future<void> _persist() async {
    final VaultSession? session = _session;
    final SecretKey? dek = _dek;
    final VaultEnvelope? envelope = _envelope;
    if (session == null || dek == null || envelope == null) return;

    try {
      final VaultEnvelope updated = await VaultCipher.reseal(
        envelope: envelope,
        dek: dek,
        plaintext: jsonEncode(session.data.toBackupMap()),
      );
      await _store.write(updated);
      _envelope = updated;
    } on AppFailure {
      rethrow;
    } catch (error, stack) {
      throw StorageFailure(
        'No se pudieron guardar los cambios en el navegador.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  VaultSession get _requireSession {
    final VaultSession? session = _session;
    if (session == null) {
      throw const SecurityFailure('La bóveda está bloqueada.');
    }
    return session;
  }

  @override
  WalletRepository get wallets => VaultWalletRepository(_requireSession);

  @override
  CategoryRepository get categories => VaultCategoryRepository(_requireSession);

  @override
  TransactionRepository get transactions =>
      VaultTransactionRepository(_requireSession);

  @override
  BudgetRepository get budgets => VaultBudgetRepository(_requireSession);

  @override
  AnalyticsRepository get analytics => VaultAnalyticsRepository(_requireSession);

  @override
  SettingsRepository get settings => VaultSettingsRepository(_requireSession);

  @override
  RecurringRepository get recurring => VaultRecurringRepository(_requireSession);

  @override
  BackupPort get backup => _WebBackupPort(this);
}

/// Import y export del JSON, sobre la bóveda en memoria.
class _WebBackupPort implements BackupPort {
  _WebBackupPort(this._backend);

  final WebBackend _backend;

  VaultData get _data => _backend._requireSession.data;

  @override
  Future<Map<String, dynamic>> buildBackupMap() async {
    await _backend.flush();
    final Map<String, dynamic> data = _data.toBackupMap();
    return <String, dynamic>{
      'magic': AppConstants.backupMagic,
      'format_version': AppConstants.backupFormatVersion,
      'schema_version': AppConstants.databaseVersion,
      'app_name': AppConstants.appName,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'counts': _data.counts,
      'checksum': await _sha256(jsonEncode(data)),
      'data': data,
    };
  }

  @override
  Future<String> exportToJsonString() async =>
      const JsonEncoder.withIndent('  ').convert(await buildBackupMap());

  @override
  Future<BackupSummary> inspect(String jsonSource) async {
    final Map<String, dynamic> root = _decode(jsonSource);
    final Map<String, dynamic> data = root['data'] as Map<String, dynamic>;
    final VaultData parsed = VaultData.fromBackupMap(data);

    final Object? stored = root['checksum'];
    final bool checksumOk = stored is String &&
        stored.isNotEmpty &&
        stored == await _sha256(jsonEncode(data));

    return BackupSummary(
      counts: parsed.counts,
      checksumOk: checksumOk,
      exportedAt: DateTime.tryParse(root['exported_at']?.toString() ?? ''),
      formatVersion: (root['format_version'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<BackupImportResult> importFromJson(
    String jsonSource, {
    bool replaceExisting = true,
  }) async {
    final Map<String, dynamic> root = _decode(jsonSource);
    final VaultData incoming =
        VaultData.fromBackupMap(root['data'] as Map<String, dynamic>);

    final VaultSession session = _backend._requireSession;
    if (replaceExisting) {
      session.data.replaceWith(incoming);
    } else {
      session.data.mergeFrom(incoming);
    }

    session.touch();
    // Se fuerza el volcado: una restauración no puede quedarse esperando al
    // temporizador de agrupación.
    await session.flush();

    return BackupImportResult(
      inserted: incoming.counts,
      skipped: const <String, int>{},
      exportedAt: DateTime.tryParse(root['exported_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> _decode(String jsonSource) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonSource);
    } catch (error, stack) {
      throw BackupFormatFailure(
        'El fichero no es un JSON válido.',
        cause: error,
        stackTrace: stack,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatFailure(
        'El fichero no tiene la estructura de una copia de esta app.',
      );
    }
    if (decoded['magic'] != AppConstants.backupMagic) {
      throw const BackupFormatFailure(
        'Este fichero no es una copia de seguridad de esta app.',
      );
    }
    final int version = (decoded['format_version'] as num?)?.toInt() ?? 0;
    if (version > AppConstants.backupFormatVersion) {
      throw BackupFormatFailure(
        'La copia se creó con una versión más nueva de la app (formato '
        '$version).',
      );
    }
    if (decoded['data'] is! Map<String, dynamic>) {
      throw const BackupFormatFailure('La copia no contiene datos.');
    }
    return decoded;
  }

  static Future<String> _sha256(String input) async {
    final Hash hash = await Sha256().hash(utf8.encode(input));
    return hash.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
