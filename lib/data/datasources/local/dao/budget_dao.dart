import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/budget_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `budgets` y cálculo de su consumo.
class BudgetDao {
  BudgetDao(this._provider);

  final DatabaseProvider _provider;

  Future<List<BudgetEntity>> findAll({bool includeDeleted = false}) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableBudgets,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'month_key DESC, category_id ASC',
    );
    return rows.map(budgetFromMap).toList(growable: false);
  }

  Future<BudgetEntity?> findById(String id) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableBudgets,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : budgetFromMap(rows.first);
  }

  /// Presupuestos VIGENTES en [month] con su gasto consumido.
  ///
  /// Aquí esta la regla de herencia que evita reconfigurar los límites cada
  /// día 1: para cada categoría (y para el global) se toma
  ///
  ///   1. el presupuesto puntual de ese mes (`month_key = '2026-08'`), si existe;
  ///   2. y si no, la plantilla mensual (`month_key IS NULL`).
  ///
  /// El `NOT EXISTS` de la consulta implementa ese "y si no". Se escribe así,
  /// y no con una funcion de ventana, porque `ROW_NUMBER() OVER (...)` exige
  /// SQLite 3.25+ y no merece la pena atar la app a la versión de SQLCipher
  /// que traiga cada dispositivo.
  ///
  /// El gasto del presupuesto global suma TODAS las categorías; el de un
  /// presupuesto por categoría solo la suya. Esa es la condicion
  /// `b.category_id IS NULL OR t.category_id = b.category_id`.
  static const String _progressSql = '''
    SELECT
      b.id, b.category_id, b.month_key, b.limit_cents,
      b.is_deleted, b.created_at, b.updated_at,
      c.name        AS category_name,
      c.icon_code   AS category_icon,
      c.color_value AS category_color,
      c.sort_order  AS category_order,
      COALESCE((
        SELECT SUM(t.amount_cents)
        FROM "transactions" t
        JOIN wallets w ON w.id = t.wallet_id
        WHERE t.is_deleted = 0
          AND w.is_archived = 0
          AND t.type = 'expense'
          AND t.occurred_at >= ?
          AND t.occurred_at <  ?
          AND (b.category_id IS NULL OR t.category_id = b.category_id)
      ), 0) AS spent_cents
    FROM budgets b
    LEFT JOIN categories c ON c.id = b.category_id
    WHERE b.is_deleted = 0
      AND (
        b.month_key = ?
        OR (
          b.month_key IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM budgets b2
            WHERE b2.is_deleted = 0
              AND b2.month_key = ?
              AND (
                b2.category_id = b.category_id
                OR (b2.category_id IS NULL AND b.category_id IS NULL)
              )
          )
        )
      )
    ORDER BY (b.category_id IS NULL) DESC, c.sort_order ASC, c.name ASC
  ''';

  Future<List<BudgetProgress>> progressForMonth(DateTime month) async {
    final Database db = await _provider.database();
    final DateRange range = DateRange.monthOf(month);
    final String key = range.monthKey;

    final List<Map<String, Object?>> rows = await db.rawQuery(
      _progressSql,
      <Object?>[range.startMs, range.endMs, key, key],
    );

    return rows
        .map((Map<String, Object?> m) => BudgetProgress(
              budget: budgetFromMap(m),
              spentCents: asInt(m['spent_cents']),
              monthKey: key,
              categoryName: asStringOrNull(m['category_name']),
              categoryIconCode: m['category_icon'] == null
                  ? null
                  : asInt(m['category_icon']),
              categoryColor: m['category_color'] == null
                  ? null
                  : asInt(m['category_color']),
            ))
        .toList(growable: false);
  }

  /// Presupuesto GLOBAL vigente del mes: el que gobierna a la mascota.
  Future<BudgetProgress?> globalProgressForMonth(DateTime month) async {
    final List<BudgetProgress> all = await progressForMonth(month);
    for (final BudgetProgress p in all) {
      if (p.budget.isGlobal) return p;
    }
    return null;
  }

  /// Guarda respetando el índice único `(categoría, mes)`.
  ///
  /// `ConflictAlgorithm.replace` no sirve aquí: reemplazaria por `id`, no por
  /// la pareja lógica, y acabariamos con dos presupuestos vivos de la misma
  /// categoría y mes. Se comprueba a mano dentro de una transacción.
  Future<void> upsert(BudgetEntity budget) async {
    final Database db = await _provider.database();
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        DatabaseSchema.tableBudgets,
        where: 'is_deleted = 0 AND id <> ? '
            'AND COALESCE(category_id, ?) = COALESCE(?, ?) '
            'AND COALESCE(month_key, ?) = COALESCE(?, ?)',
        whereArgs: <Object?>[
          budget.id,
          '@global', budget.categoryId, '@global',
          '@every', budget.monthKey, '@every',
        ],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Ya habia uno para esa pareja: se actualiza en lugar de duplicar.
        await txn.update(
          DatabaseSchema.tableBudgets,
          <String, Object?>{
            'limit_cents': budget.limitCents,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[existing.first['id']],
        );
        return;
      }

      await txn.insert(
        DatabaseSchema.tableBudgets,
        budget.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
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

  /// Ids de categoría que YA tienen presupuesto vigente en el mes. La UI las
  /// oculta del selector al crear uno nuevo para no ofrecer duplicados.
  Future<Set<String?>> occupiedCategoryIds(DateTime month) async {
    final List<BudgetProgress> progress = await progressForMonth(month);
    return progress.map((BudgetProgress p) => p.budget.categoryId).toSet();
  }
}
