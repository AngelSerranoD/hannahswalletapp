import '../../../../core/error/failures.dart';
import '../../../../domain/entities/recurring_rule_entity.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../../domain/entities/wallet_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../vault_data.dart';
import 'vault_queries.dart';
import 'vault_session.dart';

class VaultWalletRepository implements WalletRepository {
  VaultWalletRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<WalletEntity>> getWallets({bool includeArchived = false}) async {
    final List<WalletEntity> list = _d.wallets.values
        .where((WalletEntity w) => includeArchived || !w.isArchived)
        .toList()
      ..sort((WalletEntity a, WalletEntity b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  @override
  Future<List<WalletWithBalance>> getWalletsWithBalance() async {
    final List<WalletEntity> wallets = await getWallets();
    return wallets
        .map((WalletEntity w) => WalletWithBalance(
              wallet: w,
              balanceCents: VaultQueries.walletBalance(_d, w),
            ))
        .toList(growable: false);
  }

  @override
  Future<WalletEntity?> getById(String id) async => _d.wallets[id];

  @override
  Future<WalletEntity?> getDefault() async {
    final List<WalletEntity> list = await getWallets();
    if (list.isEmpty) return null;
    return list.firstWhere(
      (WalletEntity w) => w.isDefault,
      orElse: () => list.first,
    );
  }

  @override
  Future<void> create(WalletEntity wallet) async {
    if (wallet.name.trim().isEmpty) {
      throw const ValidationFailure('La cartera necesita un nombre.');
    }
    if (wallet.isDefault) _clearDefault(wallet.id);
    _d.wallets[wallet.id] = wallet;
    _session.touch();
  }

  @override
  Future<void> update(WalletEntity wallet) async {
    if (wallet.name.trim().isEmpty) {
      throw const ValidationFailure('La cartera necesita un nombre.');
    }
    if (wallet.isDefault) _clearDefault(wallet.id);
    _d.wallets[wallet.id] = wallet;
    _session.touch();
  }

  @override
  Future<void> archive(String id) async {
    final int active =
        _d.wallets.values.where((WalletEntity w) => !w.isArchived).length;
    if (active <= 1) {
      throw const ValidationFailure('Debe quedar al menos una cartera activa.');
    }
    final WalletEntity? w = _d.wallets[id];
    if (w == null) return;
    _d.wallets[id] = w.copyWith(isArchived: true, isDefault: false);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final WalletEntity? w = _d.wallets[id];
    if (w == null) return;
    _d.wallets[id] = w.copyWith(isArchived: false);
    _session.touch();
  }

  @override
  Future<void> deleteForever(String id) async {
    _d.wallets.remove(id);
    // Replica el ON DELETE CASCADE de SQLite: sin esto quedarían movimientos
    // apuntando a una cartera inexistente y los saldos dejarían de cuadrar.
    _d.transactions.removeWhere(
      (_, TransactionEntity t) => t.walletId == id,
    );
    _d.recurring.removeWhere((_, RecurringRuleEntity r) => r.walletId == id);
    _session.touch();
  }

  void _clearDefault(String exceptId) {
    for (final MapEntry<String, WalletEntity> e in _d.wallets.entries.toList()) {
      if (e.key != exceptId && e.value.isDefault) {
        _d.wallets[e.key] = e.value.copyWith(isDefault: false);
      }
    }
  }
}
