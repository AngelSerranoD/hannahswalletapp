import '../../../../core/error/failures.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../domain/entities/recurring_rule_entity.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../vault_data.dart';
import 'vault_session.dart';

class VaultRecurringRepository implements RecurringRepository {
  VaultRecurringRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  static const int _maxCatchUpPerRule = 120;

  @override
  Future<List<RecurringRuleEntity>> getAll({bool onlyActive = false}) async {
    final List<RecurringRuleEntity> list = _d.recurring.values
        .where((RecurringRuleEntity r) =>
            !r.isDeleted && (!onlyActive || r.isActive))
        .toList()
      ..sort((RecurringRuleEntity a, RecurringRuleEntity b) =>
          a.nextRunAt.compareTo(b.nextRunAt));
    return list;
  }

  @override
  Future<RecurringRuleEntity?> getById(String id) async => _d.recurring[id];

  @override
  Future<void> create(RecurringRuleEntity rule) async {
    _validate(rule);
    _d.recurring[rule.id] = rule;
    _session.touch();
  }

  @override
  Future<void> update(RecurringRuleEntity rule) async {
    _validate(rule);
    _d.recurring[rule.id] = rule;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final RecurringRuleEntity? r = _d.recurring[id];
    if (r == null) return;
    _d.recurring[id] = r.copyWith(isDeleted: true, isActive: false);
    _session.touch();
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final RecurringRuleEntity? r = _d.recurring[id];
    if (r == null) return;
    _d.recurring[id] = r.copyWith(isActive: active);
    _session.touch();
  }

  @override
  Future<int> materializeDue() async {
    final DateTime now = DateTime.now();
    int created = 0;

    for (final RecurringRuleEntity rule in await getAll(onlyActive: true)) {
      if (rule.nextRunAt.isAfter(now)) continue;

      DateTime cursor = rule.nextRunAt;
      DateTime? lastRun = rule.lastRunAt;
      int guard = 0;

      while (!cursor.isAfter(now) && guard < _maxCatchUpPerRule) {
        final DateTime? end = rule.endAt;
        if (end != null && cursor.isAfter(end)) break;

        final DateTime stamp = DateTime.now();
        final TransactionEntity tx = TransactionEntity(
          id: IdGenerator.newId(),
          walletId: rule.walletId,
          categoryId: rule.categoryId,
          type: rule.type,
          amountCents: rule.amountCents,
          note: rule.note,
          occurredAt: cursor,
          recurringRuleId: rule.id,
          createdAt: stamp,
          updatedAt: stamp,
        );
        _d.transactions[tx.id] = tx;
        created++;

        lastRun = cursor;
        cursor = rule.advanceFrom(cursor);
        guard++;
      }

      final DateTime? end = rule.endAt;
      final bool finished = end != null && cursor.isAfter(end);
      _d.recurring[rule.id] = rule.copyWith(
        nextRunAt: cursor,
        lastRunAt: lastRun,
        isActive: !finished,
      );
    }

    if (created > 0) _session.touch();
    return created;
  }

  void _validate(RecurringRuleEntity rule) {
    if (rule.amountCents <= 0) {
      throw const ValidationFailure('El importe debe ser mayor que cero.');
    }
    if (rule.intervalCount <= 0) {
      throw const ValidationFailure('El intervalo debe ser al menos 1.');
    }
    if (rule.type == TransactionType.transfer) {
      throw const ValidationFailure(
        'Los traspasos no pueden programarse como recurrentes.',
      );
    }
  }
}

// =========================================================================
//  Consultas
// =========================================================================
