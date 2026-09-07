import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../domain/entities/wallet_entity.dart';
import '../../../models/entity_mappers.dart';
import '../database_provider.dart';
import '../database_schema.dart';

/// Acceso a la tabla `wallets`.
class WalletDao {
  WalletDao(this._provider);

  final DatabaseProvider _provider;

  Future<List<WalletEntity>> findAll({bool includeArchived = false}) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableWallets,
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'is_archived ASC, sort_order ASC, created_at ASC',
    );
    return rows.map(walletFromMap).toList(growable: false);
  }

  Future<WalletEntity?> findById(String id) async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableWallets,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : walletFromMap(rows.first);
  }

  /// Cartera preseleccionada al abrir el formulario de nuevo movimiento.
  Future<WalletEntity?> findDefault() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseSchema.tableWallets,
      where: 'is_archived = 0',
      orderBy: 'is_default DESC, sort_order ASC, created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : walletFromMap(rows.first);
  }

  /// Carteras con su saldo, calculado integramente en SQL.
  ///
  /// El saldo se calcula, nunca se almacena. Un campo `balance` denormalizado
  /// se desincroniza en cuanto se edita o borra un movimiento antiguo, y
  /// entonces no hay forma de saber cual de los dos numeros miente.
  Future<List<WalletWithBalance>> findAllWithBalance() async {
    final Database db = await _provider.database();
    final List<WalletEntity> wallets = await findAll();
    final List<Map<String, Object?>> balances =
        await db.rawQuery(DatabaseSchema.queryWalletBalances);

    final Map<String, int> byId = <String, int>{
      for (final Map<String, Object?> row in balances)
        row['wallet_id']! as String: asInt(row['balance_cents']),
    };

    return wallets
        .map((WalletEntity w) => WalletWithBalance(
              wallet: w,
              balanceCents: byId[w.id] ?? w.initialBalanceCents,
            ))
        .toList(growable: false);
  }

  Future<int> balanceOf(String walletId) async {
    final List<WalletWithBalance> all = await findAllWithBalance();
    for (final WalletWithBalance w in all) {
      if (w.wallet.id == walletId) return w.balanceCents;
    }
    return 0;
  }

  Future<void> insert(WalletEntity wallet) async {
    final Database db = await _provider.database();
    await db.transaction((Transaction txn) async {
      if (wallet.isDefault) await _clearDefault(txn);
      await txn.insert(
        DatabaseSchema.tableWallets,
        wallet.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<void> update(WalletEntity wallet) async {
    final Database db = await _provider.database();
    await db.transaction((Transaction txn) async {
      if (wallet.isDefault) await _clearDefault(txn, exceptId: wallet.id);
      await txn.update(
        DatabaseSchema.tableWallets,
        wallet.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[wallet.id],
      );
    });
  }

  /// Archiva la cartera en lugar de borrarla.
  ///
  /// Borrarla dispararia el `ON DELETE CASCADE` y se llevaría por delante todo
  /// su historial de movimientos, falseando las estadísticas de meses ya
  /// cerrados. Archivar la saca de los selectores y del saldo total, pero deja
  /// el pasado donde estaba.
  Future<void> archive(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableWallets,
      <String, Object?>{
        'is_archived': 1,
        'is_default': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> restore(String id) async {
    final Database db = await _provider.database();
    await db.update(
      DatabaseSchema.tableWallets,
      <String, Object?>{
        'is_archived': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Borrado fisico. Solo desde Ajustes, avisando de que arrastra movimientos.
  Future<void> deleteForever(String id) async {
    final Database db = await _provider.database();
    await db.delete(
      DatabaseSchema.tableWallets,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> countActive() async {
    final Database db = await _provider.database();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM wallets WHERE is_archived = 0',
    );
    return asInt(rows.first['c']);
  }

  Future<void> _clearDefault(Transaction txn, {String? exceptId}) async {
    await txn.update(
      DatabaseSchema.tableWallets,
      <String, Object?>{'is_default': 0},
      where: exceptId == null ? 'is_default = 1' : 'is_default = 1 AND id <> ?',
      whereArgs: exceptId == null ? null : <Object?>[exceptId],
    );
  }
}
