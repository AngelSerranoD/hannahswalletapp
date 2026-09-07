import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `transactions`.
class TransactionDao {
  TransactionDao(this._provider);

  final DatabaseProvider _provider;

  /// SELECT comun a todas las listas: trae en una sola pasada el movimiento,
  /// su cartera, su categoría y (si es traspaso) la cartera de destino.
  static const String _viewSelect = '''
    SELECT
      t.*,
      w.name        AS wallet_name,
      w.color_value AS wallet_color,
      c.name        AS category_name,
      c.icon_code   AS category_icon,
      c.color_value AS category_color,
      dw.name       AS transfer_wallet_name
    FROM "transactions" t
    JOIN wallets w         ON w.id = t.wallet_id
    LEFT JOIN categories c ON c.id = t.category_id
    LEFT JOIN wallets dw   ON dw.id = t.transfer_wallet_id
  ''';

  /// Movimientos recientes para el dashboard.
  ///
  /// Se pagina con [limit]/[offset] en vez de traerlo todo: tras un año de uso
  /// hay miles de filas y construir esa lista entera en memoria en cada
  /// refresco tira el frame rate del scroll.
  Future<List<TransactionView>> findRecent({
    int limit = 50,
    int offset = 0,
    String? walletId,
  }) async {
    final Database db = await _provider.database();
    final List<Object?> args = <Object?>[];
    final StringBuffer sql = StringBuffer(_viewSelect)
      ..write(' WHERE t.is_deleted = 0 AND w.is_archived = 0');

    if (walletId != null) {
      sql.write(' AND (t.wallet_id = ? OR t.transfer_wallet_id = ?)');
      args
        ..add(walletId)
        ..add(walletId);
    }

    sql.write(' ORDER BY t.occurred_at DESC, t.created_at DESC LIMIT ? OFFSET ?');
    args
      ..add(limit)
      ..add(offset);

    final List<Map<String, Object?>> rows = await db.rawQuery(sql.toString(), args);
    return rows.map(transactionViewFromJoin).toList(growable: false);
  }

  /// Movimientos de un intervalo `[start, end)`.
  Future<List<TransactionView>> findInRange(
    DateRange range, {
    String? walletId,
    String? categoryId,
    TransactionType? type,
  }) async {
    final Database db = await _provider.database();
    final List<Object?> args = <Object?>[range.startMs, range.endMs];
    final StringBuffer sql = StringBuffer(_viewSelect)
      ..write(' WHERE t.is_deleted = 0 AND w.is_archived = 0')
      ..write(' AND t.occurred_at >= ? AND t.occurred_at < ?');

    if (walletId != null) {
      sql.write(' AND t.wallet_id = ?');
      args.add(walletId);
    }
    if (categoryId != null) {
      sql.write(' AND t.category_id = ?');
      args.add(categoryId);
    }
    if (type != null) {
      sql.write(' AND t.type = ?');
      args.add(type.dbValue);
    }

    sql.write(' ORDER BY t.occurred_at DESC, t.created_at DESC');
    final List<Map<String, Object?>> rows = await db.rawQuery(sql.toString(), args);
    return rows.map(transactionViewFromJoin).toList(growable: false);
  }

  /// Busqueda por texto de la nota o del nombre de la categoría.
  Future<List<TransactionView>> search(String term, {int limit = 100}) async {
    final Database db = await _provider.database();
    final String pattern = '%${term.trim()}%';
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_viewSelect'
      ' WHERE t.is_deleted = 0 AND w.is_archived = 0'
      ' AND (t.note LIKE ? COLLATE NOCASE OR c.name LIKE ? COLLATE NOCASE)'
      ' ORDER BY t.occurred_at DESC LIMIT ?',
      <Object?>[pattern, pattern, limit],
    );
    return rows.map(transactionViewFromJoin).toList(growable: false);
  }

  Future<TransactionView?> findById(String id) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_viewSelect WHERE t.id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : transactionViewFromJoin(rows.first);
  }

  Future<void> insert(TransactionEntity tx) async {
    final Database db = await _provider.database();
    await db.insert(
      DatabaseSchema.tableTransactions,
      tx.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(TransactionEntity tx) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableTransactions,
      tx.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[tx.id],
    );
  }

  /// Borrado lógico, para que el "Deshacer" del snackbar sea instantaneo y no
  /// haya que reconstruir la fila con sus relaciones.
  Future<void> softDelete(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableTransactions,
      <String, Object?>{
        'is_deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> restore(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableTransactions,
      <String, Object?>{
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Vacia definitivamente los borrados con mas de [olderThanDays] días.
  /// Lo llama Ajustes; no se ejecuta solo, para que "Deshacer" siempre exista.
  Future<int> purgeDeleted({int olderThanDays = 30}) async {
    final Database db = await _provider.database();
    final int cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    return db.delete(
      DatabaseSchema.tableTransactions,
      where: 'is_deleted = 1 AND updated_at < ?',
      whereArgs: <Object?>[cutoff],
    );
  }

  Future<int> countAll() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM "transactions" WHERE is_deleted = 0',
    );
    return asInt(rows.first['c']);
  }

  /// Fecha del movimiento mas antiguo. La usa la pantalla de estadísticas para
  /// no dejar retroceder mas alla del primer dato.
  Future<DateTime?> earliestDate() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT MIN(occurred_at) AS m FROM "transactions" WHERE is_deleted = 0',
    );
    final Object? value = rows.first['m'];
    return value == null ? null : asDate(value);
  }
}
