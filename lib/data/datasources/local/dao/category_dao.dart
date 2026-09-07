import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../domain/entities/category_entity.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `categories`, con borrado lógico via `is_deleted`.
class CategoryDao {
  CategoryDao(this._provider);

  final DatabaseProvider _provider;

  /// Categorías vivas. [type] filtra gasto/ingreso; `null` devuelve ambas.
  Future<List<CategoryEntity>> findAll({
    TransactionType? type,
    bool includeDeleted = false,
  }) async {
    final Database db = await _provider.database();

    final List<String> clauses = <String>[];
    final List<Object?> args = <Object?>[];
    if (!includeDeleted) clauses.add('is_deleted = 0');
    if (type != null) {
      clauses.add('type = ?');
      args.add(type.dbValue);
    }

    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableCategories,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(categoryFromMap).toList(growable: false);
  }

  Future<CategoryEntity?> findById(String id) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableCategories,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : categoryFromMap(rows.first);
  }

  Future<void> insert(CategoryEntity category) async {
    final Database db = await _provider.database();
    await db.insert(
      DatabaseSchema.tableCategories,
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(CategoryEntity category) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableCategories,
      category.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[category.id],
    );
  }

  /// Borrado LOGICO: marca `is_deleted = 1`.
  ///
  /// Este es el motivo de que la columna exista. Si se borrase la fila, el
  /// `ON DELETE SET NULL` de `transactions.category_id` dejaria sin categoría
  /// todos los gastos historicos y el gráfico del año pasado cambiaría solo
  /// por haber ordenado la lista de categorías hoy.
  Future<void> softDelete(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableCategories,
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
      DatabaseSchema.tableCategories,
      <String, Object?>{
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Cuantos movimientos vivos usan la categoría. La UI lo muestra al borrar
  /// para que se sepa a cuantos apuntes afecta.
  Future<int> usageCount(String categoryId) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM "transactions" '
      'WHERE category_id = ? AND is_deleted = 0',
      <Object?>[categoryId],
    );
    return asInt(rows.first['c']);
  }

  Future<void> reorder(List<String> orderedIds) async {
    final Database db = await _provider.database();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Batch batch = db.batch();
    for (int i = 0; i < orderedIds.length; i++) {
      batch.update(
        DatabaseSchema.tableCategories,
        <String, Object?>{'sort_order': i, 'updated_at': now},
        where: 'id = ?',
        whereArgs: <Object?>[orderedIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> nextSortOrder(TransactionType type) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next '
      'FROM categories WHERE type = ?',
      <Object?>[type.dbValue],
    );
    return asInt(rows.first['next']);
  }
}
