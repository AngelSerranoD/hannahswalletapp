import 'package:idb_shim/idb_browser.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import 'vault_envelope.dart';

/// Registro de intentos fallidos de contraseña.
///
/// Se guarda SIN cifrar y a propósito: si viviera dentro de la bóveda, habría
/// que descifrarla para saber cuántos intentos van, y descifrarla es justo lo
/// que se está intentando limitar. No revela nada: es un contador y una marca
/// de tiempo.
class AttemptRecord {
  const AttemptRecord({this.failures = 0, this.lockedUntil});

  factory AttemptRecord.fromMap(Map<String, Object?> map) => AttemptRecord(
        failures: (map['failures'] as num?)?.toInt() ?? 0,
        lockedUntil: map['locked_until'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (map['locked_until']! as num).toInt(),
              ),
      );

  final int failures;
  final DateTime? lockedUntil;

  bool get isLocked =>
      lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  Duration get remaining {
    final DateTime? until = lockedUntil;
    if (until == null) return Duration.zero;
    final Duration left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'failures': failures,
        'locked_until': lockedUntil?.millisecondsSinceEpoch,
      };
}

/// Persistencia del blob cifrado en el navegador.
///
/// Se usa IndexedDB y no `localStorage` por dos motivos que importan:
///
///  * `localStorage` está limitado a unos 5 MB y guarda solo texto, así que un
///    historial largo en base64 lo desbordaría; IndexedDB llega, en iOS 17+, a
///    un 20 % del disco para una web app instalada.
///  * `localStorage` es SÍNCRONO: escribir varios megas bloquearía el hilo
///    principal y la interfaz daría tirones en cada guardado.
class VaultStore {
  VaultStore({IdbFactory? factory}) : _factory = factory;

  final IdbFactory? _factory;
  Database? _db;

  IdbFactory get _idb {
    final IdbFactory? provided = _factory;
    if (provided != null) return provided;
    if (!idbFactoryNativeSupported) {
      throw const StorageFailure(
        'Este navegador no permite almacenamiento local (IndexedDB). '
        'En iOS, comprueba que no estás en una ventana privada.',
      );
    }
    return idbFactoryNative;
  }

  Future<Database> _open() async {
    final Database? existing = _db;
    if (existing != null) return existing;

    try {
      final Database db = await _idb.open(
        AppConstants.webVaultDbName,
        version: 1,
        onUpgradeNeeded: (VersionChangeEvent event) {
          final Database db = event.database;
          if (!db.objectStoreNames.contains(AppConstants.webVaultStoreName)) {
            db.createObjectStore(AppConstants.webVaultStoreName);
          }
        },
      );
      _db = db;
      return db;
    } catch (error, stack) {
      throw StorageFailure(
        'No se pudo abrir el almacén local del navegador.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  Future<Object?> _read(String key) async {
    final Database db = await _open();
    final Transaction txn = db.transaction(
      AppConstants.webVaultStoreName,
      idbModeReadOnly,
    );
    final Object? raw =
        await txn.objectStore(AppConstants.webVaultStoreName).getObject(key);
    await txn.completed;
    return raw;
  }

  Future<void> _write(String key, Map<String, Object?> value) async {
    final Database db = await _open();
    final Transaction txn = db.transaction(
      AppConstants.webVaultStoreName,
      idbModeReadWrite,
    );
    await txn.objectStore(AppConstants.webVaultStoreName).put(value, key);
    // Esperar a `completed` no es opcional: la transacción de IndexedDB no ha
    // confirmado nada hasta ese momento, y si la pestaña se cierra antes se
    // pierde el guardado.
    await txn.completed;
  }

  static Map<String, Object?> _asMap(Object raw) => <String, Object?>{
        for (final MapEntry<dynamic, dynamic> e in (raw as Map).entries)
          e.key.toString(): e.value,
      };

  /// `true` si ya hay una bóveda creada en este dispositivo.
  Future<bool> exists() async => (await read()) != null;

  Future<VaultEnvelope?> read() async {
    final Object? raw = await _read(AppConstants.webVaultRecordKey);
    if (raw == null) return null;
    if (raw is! Map) {
      throw const StorageFailure('El almacén local está dañado.');
    }
    return VaultEnvelope.fromMap(_asMap(raw));
  }

  Future<void> write(VaultEnvelope envelope) =>
      _write(AppConstants.webVaultRecordKey, envelope.toMap());

  // -------------------------------------------------- Intentos fallidos

  Future<AttemptRecord> readAttempts() async {
    final Object? raw = await _read(AppConstants.webVaultAttemptsKey);
    if (raw is! Map) return const AttemptRecord();
    return AttemptRecord.fromMap(_asMap(raw));
  }

  Future<void> writeAttempts(AttemptRecord record) =>
      _write(AppConstants.webVaultAttemptsKey, record.toMap());

  Future<void> delete() async {
    final Database db = await _open();
    final Transaction txn = db.transaction(
      AppConstants.webVaultStoreName,
      idbModeReadWrite,
    );
    final ObjectStore store = txn.objectStore(AppConstants.webVaultStoreName);
    await store.delete(AppConstants.webVaultRecordKey);
    await store.delete(AppConstants.webVaultAttemptsKey);
    await txn.completed;
  }

  void close() {
    _db?.close();
    _db = null;
  }
}
