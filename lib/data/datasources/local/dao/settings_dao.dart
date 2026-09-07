import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database_provider.dart';
import '../database_schema.dart';

/// Preferencias de la app, guardadas DENTRO de la base cifrada.
///
/// A proposito no se usa `SharedPreferences`: ese fichero se escribe en claro
/// y filtraria detalles como la moneda o si hay bloqueo activo. Metiendolo en
/// la base SQLCipher, hasta los ajustes viajan cifrados y salen incluidos en
/// el backup JSON sin tratamiento aparte.
class SettingsDao {
  SettingsDao(this._provider);

  final DatabaseProvider _provider;

  Future<Map<String, String>> readAll() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows =
        await db.query(DatabaseSchema.tableSettings);
    return <String, String>{
      for (final Map<String, Object?> r in rows)
        r['key']! as String: (r['value'] ?? '').toString(),
    };
  }

  Future<String?> read(String key) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableSettings,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['value'] ?? '').toString();
  }

  Future<void> write(String key, String value) async {
    final Database db = await _provider.database();
    await db.insert(
      DatabaseSchema.tableSettings,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> writeAll(Map<String, String> values) async {
    final Database db = await _provider.database();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Batch batch = db.batch();
    values.forEach((String key, String value) {
      batch.insert(
        DatabaseSchema.tableSettings,
        <String, Object?>{'key': key, 'value': value, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  Future<bool> readBool(String key, {bool fallback = false}) async {
    final String? raw = await read(key);
    if (raw == null) return fallback;
    return raw.toLowerCase() == 'true' || raw == '1';
  }

  Future<void> writeBool(String key, bool value) =>
      write(key, value ? 'true' : 'false');
}
