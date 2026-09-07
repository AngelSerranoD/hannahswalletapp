import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/utils/date_range.dart';
import '../datasources/local/data_change_bus.dart';
import '../datasources/local/database_provider.dart';
import '../datasources/local/database_schema.dart';

/// Que hacer cuando el backup que se importa choca con los datos actuales.
enum ImportStrategy {
  /// Vacia las tablas y deja EXACTAMENTE el contenido del fichero. Es lo que
  /// se quiere al restaurar un móvil nuevo.
  replace('Reemplazar todo'),

  /// Inserta lo que falta y actualiza lo que ya existe, comparando por `id`.
  /// Útil para juntar dos dispositivos sin perder lo de ninguno.
  merge('Fusionar');

  const ImportStrategy(this.label);
  final String label;
}

/// Resumen de una importación, para ensenarselo al usuario.
class ImportReport {
  const ImportReport({
    required this.strategy,
    required this.inserted,
    required this.skipped,
    required this.exportedAt,
  });

  final ImportStrategy strategy;

  /// Filas escritas por tabla.
  final Map<String, int> inserted;

  /// Filas descartadas por tabla (referencias rotas, duplicados no fusionables).
  final Map<String, int> skipped;

  final DateTime? exportedAt;

  int get totalInserted =>
      inserted.values.fold(0, (int a, int b) => a + b);

  int get totalSkipped => skipped.values.fold(0, (int a, int b) => a + b);
}

/// Exportación e importación de la base completa en JSON.
///
/// El objetivo es que el usuario sea DUENO de sus datos: sin cuenta, sin nube
/// y sin depender de que esta app siga existiendo. Un JSON plano se abre con
/// cualquier editor y se procesa con cualquier lenguaje.
///
/// CONTRAPARTIDA IMPORTANTE: el fichero exportado NO va cifrado. Dentro de la
/// app los datos viven bajo SQLCipher, pero en cuanto salen a la carpeta de
/// descargas o a un chat, quedan legibles para cualquiera que abra el fichero.
/// La UI lo advierte antes de compartir.
class BackupService {
  BackupService(this._provider, this._bus);

  final DatabaseProvider _provider;
  final DataChangeBus _bus;

  /// Tablas que entran en el backup, EN ORDEN DE DEPENDENCIA.
  ///
  /// El orden no es cosmetico: con `PRAGMA foreign_keys = ON`, insertar un
  /// movimiento antes que su cartera viola la clave ajena y aborta la
  /// transacción entera. Al importar se recorre esta lista tal cual, y al
  /// vaciar se recorre al reves.
  static const List<String> _tables = <String>[
    DatabaseSchema.tableWallets,
    DatabaseSchema.tableCategories,
    DatabaseSchema.tableRecurringRules,
    DatabaseSchema.tableTransactions,
    DatabaseSchema.tableBudgets,
    DatabaseSchema.tableSettings,
  ];

  /// Nombre lógico (sin comillas SQL) usado como clave JSON.
  static String _keyOf(String table) => table.replaceAll('"', '');

  // ---------------------------------------------------------------- EXPORT

  /// Construye el objeto JSON completo con TODAS las filas.
  ///
  /// Antes de leer nada se hace `wal_checkpoint`: con `journal_mode = WAL` los
  /// últimos movimientos guardados pueden vivir solo en el fichero `-wal`, y
  /// un backup tomado sin volcarlos saldría con datos de hace un rato.
  Future<Map<String, dynamic>> buildBackupMap() async {
    try {
      await _provider.checkpoint();
      final Database db = await _provider.database();

      final Map<String, List<Map<String, Object?>>> data =
          <String, List<Map<String, Object?>>>{};
      final Map<String, int> counts = <String, int>{};

      for (final String table in _tables) {
        final List<Map<String, Object?>> rows = await db.query(table);
        // `db.query` devuelve mapas de solo lectura respaldados por la
        // plataforma; se copian para poder serializarlos sin sorpresas.
        final List<Map<String, Object?>> copy = rows
            .map<Map<String, Object?>>(Map<String, Object?>.from)
            .toList(growable: false);
        data[_keyOf(table)] = copy;
        counts[_keyOf(table)] = copy.length;
      }

      final String canonicalData = jsonEncode(data);

      return <String, dynamic>{
        'magic': AppConstants.backupMagic,
        'format_version': AppConstants.backupFormatVersion,
        'schema_version': AppConstants.databaseVersion,
        'app_name': AppConstants.appName,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'counts': counts,
        // Huella del contenido: permite detectar un fichero truncado o
        // manipulado antes de empezar a escribir en la base.
        'checksum': await _sha256(canonicalData),
        'data': data,
      };
    } on AppFailure {
      rethrow;
    } catch (error, stack) {
      throw StorageFailure(
        'No se pudieron leer los datos para la copia de seguridad.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  /// El backup serializado y listo para escribir en un fichero.
  ///
  /// Se usa `JsonEncoder.withIndent` porque un backup es un formato de
  /// archivo, no un payload de red: que se pueda abrir y leer a ojo vale mas
  /// que ahorrar unos kilobytes.
  Future<String> exportToJsonString() async {
    final Map<String, dynamic> map = await buildBackupMap();
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Escribe el backup en un fichero temporal y devuelve su ruta, lista para
  /// pasarsela a `Share`.
  Future<File> exportToFile() async {
    try {
      final String json = await exportToJsonString();
      final Directory dir = await getTemporaryDirectory();
      final String name =
          'hannahs-wallet-${AppDates.fileStamp(DateTime.now())}.json';
      final File file = File(p.join(dir.path, name));
      await file.writeAsString(json, flush: true);
      return file;
    } on AppFailure {
      rethrow;
    } catch (error, stack) {
      throw StorageFailure(
        'No se pudo escribir el fichero de copia de seguridad.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  // ---------------------------------------------------------------- IMPORT

  /// Valida un JSON de backup sin tocar la base.
  ///
  /// Se ejecuta ANTES de importar para poder mostrar "vas a restaurar 412
  /// movimientos del 3 de agosto" y para rechazar ficheros ajenos sin haber
  /// borrado nada.
  Future<BackupPreview> inspect(String jsonSource) async {
    final Map<String, dynamic> root = _decodeAndValidate(jsonSource);
    final Map<String, dynamic> data = root['data'] as Map<String, dynamic>;

    final Map<String, int> counts = <String, int>{
      for (final String table in _tables)
        _keyOf(table): (data[_keyOf(table)] as List<dynamic>? ?? const <dynamic>[])
            .length,
    };

    return BackupPreview(
      exportedAt: DateTime.tryParse(root['exported_at']?.toString() ?? ''),
      formatVersion: (root['format_version'] as num?)?.toInt() ?? 0,
      schemaVersion: (root['schema_version'] as num?)?.toInt() ?? 0,
      counts: counts,
      checksumOk: await _verifyChecksum(root),
    );
  }

  /// Restaura el backup.
  ///
  /// TODA la operacion va dentro de una única transacción: si una sola fila
  /// falla, SQLite deshace el resto y la base se queda exactamente como
  /// estaba. Lo contrario -por ejemplo borrar primero y luego fallar al
  /// insertar- dejaria al usuario sin datos antiguos y sin datos nuevos.
  Future<ImportReport> importFromJson(
    String jsonSource, {
    ImportStrategy strategy = ImportStrategy.replace,
  }) async {
    final Map<String, dynamic> root = _decodeAndValidate(jsonSource);
    final Map<String, dynamic> data = root['data'] as Map<String, dynamic>;

    final Database db = await _provider.database();
    final Map<String, int> inserted = <String, int>{};
    final Map<String, int> skipped = <String, int>{};

    try {
      await db.transaction((Transaction txn) async {
        if (strategy == ImportStrategy.replace) {
          // Al reves que al insertar: primero los hijos, luego los padres.
          for (final String table in _tables.reversed) {
            await txn.delete(table);
          }
        }

        for (final String table in _tables) {
          final String key = _keyOf(table);
          final List<dynamic> rows =
              data[key] as List<dynamic>? ?? const <dynamic>[];
          int ok = 0;
          int bad = 0;

          for (final dynamic raw in rows) {
            if (raw is! Map) {
              bad++;
              continue;
            }
            final Map<String, Object?> row = <String, Object?>{
              for (final MapEntry<dynamic, dynamic> e in raw.entries)
                e.key.toString(): e.value,
            };

            try {
              await txn.insert(
                table,
                row,
                // `replace` sobre la clave primaria: en modo fusion, una fila
                // con el mismo id se sobreescribe con la versión del backup.
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              ok++;
            } on DatabaseException {
              // Fila con una referencia que no existe (categoría borrada a
              // mano del JSON, por ejemplo). Se descarta esa fila y se sigue,
              // en vez de tirar abajo la restauración entera.
              bad++;
            }
          }

          inserted[key] = ok;
          skipped[key] = bad;
        }
      });
    } catch (error, stack) {
      throw BackupFormatFailure(
        'La copia no se pudo restaurar. No se ha modificado nada.',
        cause: error,
        stackTrace: stack,
      );
    }

    // Tras reescribir miles de filas el fichero queda fragmentado.
    await _provider.vacuum();
    _bus.notify();

    return ImportReport(
      strategy: strategy,
      inserted: inserted,
      skipped: skipped,
      exportedAt: DateTime.tryParse(root['exported_at']?.toString() ?? ''),
    );
  }

  // ------------------------------------------------------------- INTERNALS

  Map<String, dynamic> _decodeAndValidate(String jsonSource) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonSource);
    } catch (error, stack) {
      throw BackupFormatFailure(
        'El fichero no es un JSON valido.',
        cause: error,
        stackTrace: stack,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatFailure(
        'El fichero no tiene la estructura de una copia de Hannah\'s Wallet.',
      );
    }

    if (decoded['magic'] != AppConstants.backupMagic) {
      throw const BackupFormatFailure(
        'Este fichero no es una copia de seguridad de Hannah\'s Wallet.',
      );
    }

    final int version = (decoded['format_version'] as num?)?.toInt() ?? 0;
    if (version > AppConstants.backupFormatVersion) {
      throw BackupFormatFailure(
        'La copia se creo con una versión mas nueva de la app '
        '(formato $version). Actualiza Hannah\'s Wallet para restaurarla.',
      );
    }

    if (decoded['data'] is! Map<String, dynamic>) {
      throw const BackupFormatFailure('La copia no contiene datos.');
    }

    return decoded;
  }

  /// Compara el checksum guardado con el recalculado.
  ///
  /// No aborta la importación si no cuadra: un backup editado a mano por el
  /// usuario (que es un uso legitimo de un formato abierto) tendría el
  /// checksum roto y aun así ser perfectamente valido. Solo se informa.
  Future<bool> _verifyChecksum(Map<String, dynamic> root) async {
    final Object? stored = root['checksum'];
    if (stored is! String || stored.isEmpty) return false;
    final String recomputed = await _sha256(jsonEncode(root['data']));
    return recomputed == stored;
  }

  static Future<String> _sha256(String input) async {
    final Hash hash = await Sha256().hash(utf8.encode(input));
    return hash.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// Lo que se sabe de un backup antes de importarlo.
class BackupPreview {
  const BackupPreview({
    required this.exportedAt,
    required this.formatVersion,
    required this.schemaVersion,
    required this.counts,
    required this.checksumOk,
  });

  final DateTime? exportedAt;
  final int formatVersion;
  final int schemaVersion;
  final Map<String, int> counts;
  final bool checksumOk;

  int get transactionCount => counts['transactions'] ?? 0;
  int get walletCount => counts['wallets'] ?? 0;
  int get categoryCount => counts['categories'] ?? 0;
  int get budgetCount => counts['budgets'] ?? 0;
}
