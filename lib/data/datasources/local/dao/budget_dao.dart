import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `budgets` y al gasto con el que se comparan.
///
/// Solo lee y escribe. Qué presupuesto manda en cada mes y qué combinaciones
/// son válidas lo decide `BudgetPlanner`, igual que en la versión web.
class BudgetDao {
  BudgetDao(this._provider);

  final DatabaseProvider _provider;

  Future<List<BudgetEntity>> findAll({bool includeDeleted = false}) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableBudgets,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(budgetFromMap).toList(growable: false);
  }

  /// Gasto del intervalo agrupado por categoría (`null`: sin categoría).
  ///
  /// Quedan fuera los movimientos borrados y los de carteras archivadas, igual
  /// que en el resto de totales de la app.
  static const String _spentByCategorySql = '''
    SELECT t.category_id, SUM(t.amount_cents) AS spent_cents
    FROM "transactions" t
    JOIN wallets w ON w.id = t.wallet_id
    WHERE t.is_deleted = 0
      AND w.is_archived = 0
      AND t.type = 'expense'
      AND t.occurred_at >= ?
      AND t.occurred_at <  ?
    GROUP BY t.category_id
  ''';

  Future<Map<String?, int>> spentByCategory(DateRange range) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      _spentByCategorySql,
      <Object?>[range.startMs, range.endMs],
    );
    return <String?, int>{
      for (final Map<String, Object?> row in rows)
        asStringOrNull(row['category_id']): asInt(row['spent_cents']),
    };
  }

  /// Inserta o sustituye por `id`. Las reglas ya se han aplicado antes.
  Future<void> upsert(BudgetEntity budget) async {
    final Database db = await _provider.database();
    await db.insert(
      DatabaseSchema.tableBudgets,
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableBudgets,
      <String, Object?>{
        'is_deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
