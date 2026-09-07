import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../security/encryption_key_manager.dart';
import 'database_schema.dart';
import 'seed_data.dart';

/// Puerta de entrada única a la base SQLCipher.
///
/// Nadie mas en la app llama a `openDatabase`. Los DAO reciben la instancia ya
/// abierta, lo que permite (a) inyectar una base en memoria en los tests y
/// (b) garantizar que la apertura cifrada ocurre exactamente una vez.
class DatabaseProvider {
  DatabaseProvider(this._keyManager);

  final EncryptionKeyManager _keyManager;

  Database? _database;

  /// Serializa las aperturas concurrentes.
  ///
  /// Al arrancar, varios providers de Riverpod piden la base a la vez. Sin
  /// este future compartido se dispararian dos `openDatabase` en paralelo
  /// sobre el mismo fichero, con dos derivaciones PBKDF2 y riesgo de bloqueo.
  Future<Database>? _opening;

  bool get isOpen => _database?.isOpen ?? false;

  Future<Database> database() {
    final Database? existing = _database;
    if (existing != null && existing.isOpen) return Future<Database>.value(existing);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    try {
      final String path = await resolveDatabasePath();
      final String passphrase = await _keyManager.obtainDatabasePassphrase();

      final Database db = await openDatabase(
        path,
        password: passphrase,
        version: AppConstants.databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: _onOpen,
      );

      _database = db;
      return db;
    } on AppFailure {
      rethrow;
    } on DatabaseException catch (error, stack) {
      // Un "file is not a database" aquí significa casi siempre que el fichero
      // sigue en disco pero el Keystore se limpio (app reinstalada, datos
      // borrados, restauración en otro móvil): sin la clave el .db es ruido.
      throw DatabaseFailure(
        'No se pudo abrir la base cifrada. Es posible que la clave de este '
        'dispositivo ya no coincida con el fichero.',
        cause: error,
        stackTrace: stack,
      );
    } catch (error, stack) {
      throw DatabaseFailure(
        'Fallo inesperado al inicializar la base de datos.',
        cause: error,
        stackTrace: stack,
      );
    }
  }

  /// Ruta del fichero dentro del almacenamiento privado de la app.
  ///
  /// En Android es el directorio interno, no accesible por otras apps ni por
  /// el usuario sin root. En iOS, el sandbox de documentos de soporte.
  static Future<String> resolveDatabasePath() async {
    final Directory dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, AppConstants.databaseFileName);
  }

  /// Se ejecuta ANTES de `onCreate`/`onUpgrade`, en cada apertura.
  Future<void> _onConfigure(Database db) async {
    // Sin esto SQLite ignora silenciosamente las claves ajenas: se podrían
    // insertar movimientos apuntando a carteras inexistentes.
    await db.execute('PRAGMA foreign_keys = ON');

    // WAL: lectores y escritor no se bloquean entre si. En esta app el
    // dashboard esta leyendo mientras se guarda un gasto, y con el journal
    // clasico esa lectura se quedaría esperando y se veria un tiron en la UI.
    // Devuelve una fila con el modo resultante, por eso es rawQuery.
    await db.rawQuery('PRAGMA journal_mode = WAL');

    // FULL: cada commit hace fsync antes de dar por bueno el guardado. Es mas
    // lento que NORMAL, pero aquí se trata del dinero del usuario y en un
    // móvil el corte de energía es que se agote la batería a media escritura.
    // La durabilidad gana a los milisegundos.
    await db.execute('PRAGMA synchronous = FULL');

    // Limita el crecimiento del WAL. Sin tope, un mes de uso intenso deja un
    // -wal de decenas de MB que solo se poda al cerrar la app.
    await db.execute('PRAGMA wal_autocheckpoint = 256');

    // Las tablas temporales de los GROUP BY de estadísticas van a RAM.
    await db.execute('PRAGMA temp_store = MEMORY');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((Transaction txn) async {
      for (final String statement in DatabaseSchema.createStatements) {
        await txn.execute(statement);
      }
      for (final String statement in DatabaseSchema.indexStatements) {
        await txn.execute(statement);
      }
      await SeedData.populate(txn);
    });
  }

  /// Migraciones incrementales.
  ///
  /// Se deja el esqueleto listo (y no un `throw`) para que la versión 2 sea
  /// añadir un `case` sin tocar nada mas. Cada paso debe ser idempotente y no
  /// destruir datos: esta base no tiene copia en ningún servidor.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      switch (v) {
        // case 2:
        //   await db.execute('ALTER TABLE "transactions" ADD COLUMN tag TEXT');
        //   break;
        default:
          break;
      }
    }
  }

  Future<void> _onOpen(Database db) async {
    // Verificacion barata de que la passphrase era correcta: si SQLCipher no
    // hubiese podido descifrar la cabecera, esta consulta lanzaria en vez de
    // devolver el número de tablas.
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
  }

  /// Fuerza el volcado del WAL al fichero principal.
  ///
  /// Imprescindible antes de exportar o copiar la base: sin esto, los últimos
  /// movimientos viven solo en el `-wal` y el backup saldría incompleto.
  Future<void> checkpoint() async {
    final Database db = await database();
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  /// Compacta el fichero tras un borrado masivo o una importación.
  Future<void> vacuum() async {
    final Database db = await database();
    await db.execute('VACUUM');
  }

  Future<void> close() async {
    final Database? db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// Borrado total: cierra, elimina el fichero (y sus `-wal`/`-shm`) y destruye
  /// la clave. Operacion irreversible que expone Ajustes con doble confirmación.
  Future<void> wipeEverything() async {
    await close();
    final String path = await resolveDatabasePath();
    for (final String suffix in <String>['', '-wal', '-shm', '-journal']) {
      final File f = File('$path$suffix');
      if (await f.exists()) {
        await f.delete();
      }
    }
    await _keyManager.destroyKeyMaterial();
  }
}
