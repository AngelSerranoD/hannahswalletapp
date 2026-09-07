import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../domain/entities/recurring_rule_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `recurring_rules`.
class RecurringDao {
  RecurringDao(this._provider);

  final DatabaseProvider _provider;

  Future<List<RecurringRuleEntity>> findAll({bool onlyActive = false}) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableRecurringRules,
      where: onlyActive ? 'is_deleted = 0 AND is_active = 1' : 'is_deleted = 0',
      orderBy: 'next_run_at ASC',
    );
    return rows.map(recurringFromMap).toList(growable: false);
  }

  /// Reglas cuya próxima ejecucion ya vencio.
  ///
  /// Incluye `end_at` para no seguir generando una suscripcion que el usuario
  /// dio de baja con fecha.
  Future<List<RecurringRuleEntity>> findDue(DateTime until) async {
    final Database db = await _provider.database();
    final int ms = until.millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableRecurringRules,
      where: 'is_deleted = 0 AND is_active = 1 AND next_run_at <= ? '
          'AND (end_at IS NULL OR next_run_at <= end_at)',
      whereArgs: <Object?>[ms],
      orderBy: 'next_run_at ASC',
    );
    return rows.map(recurringFromMap).toList(growable: false);
  }

  Future<RecurringRuleEntity?> findById(String id) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableRecurringRules,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : recurringFromMap(rows.first);
  }

  Future<void> insert(RecurringRuleEntity rule) async {
    final Database db = await _provider.database();
    await db.insert(
      DatabaseSchema.tableRecurringRules,
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(RecurringRuleEntity rule) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableRecurringRules,
      rule.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[rule.id],
    );
  }

  Future<void> softDelete(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableRecurringRules,
      <String, Object?>{
        'is_deleted': 1,
        'is_active': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setActive(String id, bool active) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableRecurringRules,
      <String, Object?>{
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
