import '../../../../core/error/failures.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../vault_data.dart';
import 'vault_queries.dart';
import 'vault_session.dart';

class VaultTransactionRepository implements TransactionRepository {
  VaultTransactionRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<TransactionView>> getRecent({
    int limit = 50,
    int offset = 0,
    String? walletId,
  }) async {
    final List<TransactionEntity> all = VaultQueries.liveTransactions(_d)
        .where((TransactionEntity t) =>
            walletId == null ||
            t.walletId == walletId ||
            t.transferWalletId == walletId)
        .toList()
      ..sort(VaultQueries.byRecency);

    return all
        .skip(offset)
        .take(limit)
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<List<TransactionView>> getInRange(
    DateRange range, {
    String? walletId,
    String? categoryId,
    TransactionType? type,
  }) async {
    final List<TransactionEntity> all = VaultQueries.liveTransactions(_d)
        .where((TransactionEntity t) =>
            range.contains(t.occurredAt) &&
            (walletId == null || t.walletId == walletId) &&
            (categoryId == null || t.categoryId == categoryId) &&
            (type == null || t.type == type))
        .toList()
      ..sort(VaultQueries.byRecency);

    return all
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<List<TransactionView>> search(String term) async {
    final String needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const <TransactionView>[];

    final List<TransactionEntity> all =
        VaultQueries.liveTransactions(_d).where((TransactionEntity t) {
      final String note = (t.note ?? '').toLowerCase();
      final String category =
          (_d.categories[t.categoryId]?.name ?? '').toLowerCase();
      return note.contains(needle) || category.contains(needle);
    }).toList()
          ..sort(VaultQueries.byRecency);

    return all
        .take(100)
        .map((TransactionEntity t) => VaultQueries.toView(_d, t))
        .toList(growable: false);
  }

  @override
  Future<TransactionView?> getById(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    return t == null ? null : VaultQueries.toView(_d, t);
  }

  @override
  Future<void> create(TransactionEntity tx) async {
    _validate(tx);
    _d.transactions[tx.id] = tx;
    _session.touch();
  }

  @override
  Future<void> update(TransactionEntity tx) async {
    _validate(tx);
    _d.transactions[tx.id] = tx;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    if (t == null) return;
    _d.transactions[id] = t.copyWith(isDeleted: true);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final TransactionEntity? t = _d.transactions[id];
    if (t == null) return;
    _d.transactions[id] = t.copyWith(isDeleted: false);
    _session.touch();
  }

  @override
  Future<int> purgeDeleted({int olderThanDays = 30}) async {
    final DateTime cutoff =
        AppClock.now().subtract(Duration(days: olderThanDays));
    final List<String> doomed = _d.transactions.values
        .where((TransactionEntity t) =>
            t.isDeleted && t.updatedAt.isBefore(cutoff))
        .map((TransactionEntity t) => t.id)
        .toList(growable: false);

    for (final String id in doomed) {
      _d.transactions.remove(id);
    }
    if (doomed.isNotEmpty) _session.touch();
    return doomed.length;
  }

  @override
  Future<DateTime?> earliestDate() async {
    DateTime? earliest;
    for (final TransactionEntity t in VaultQueries.liveTransactions(_d)) {
      if (earliest == null || t.occurredAt.isBefore(earliest)) {
        earliest = t.occurredAt;
      }
    }
    return earliest;
  }

  void _validate(TransactionEntity tx) {
    if (tx.amountCents <= 0) {
      throw const ValidationFailure('El importe debe ser mayor que cero.');
    }
    if (!_d.wallets.containsKey(tx.walletId)) {
      throw const ValidationFailure('La cartera indicada no existe.');
    }
    if (tx.isTransfer) {
      if (tx.transferWalletId == null) {
        throw const ValidationFailure('Elige la cartera de destino.');
      }
      if (tx.transferWalletId == tx.walletId) {
        throw const ValidationFailure(
          'El origen y el destino no pueden ser la misma cartera.',
        );
      }
    }
  }
}
