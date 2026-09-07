import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/recurring_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/wallet_entity.dart';

/// Traduccion entre filas de SQLite y entidades de dominio.
///
/// Se resuelve con extensiones y funciones libres en vez de duplicar cada
/// entidad en un "Model" gemelo: el dominio se mantiene limpio de SQL (no
/// importa nada de `sqflite`) sin pagar el precio de mantener dos clases
/// identicas por tabla, que es donde suelen aparecer los bugs de campos que se
/// anaden en un lado y se olvidan en el otro.
///
/// Reglas de conversion:
///   * fechas  -> INTEGER (ms desde epoch, UTC)
///   * bool    -> INTEGER 0/1
///   * enums   -> TEXT con su `dbValue`

// --- Ayudas de lectura tolerantes ---------------------------------------

/// Lee un entero venga como int, num o texto.
///
/// Necesario porque las filas del backup JSON pasan por `jsonDecode`, y ahi un
/// entero grande puede llegar como `num`; y porque `SUM()` de SQLite devuelve
/// `null` cuando no hay filas.
int asInt(Object? value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? fallback;
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final String s = value.toString().toLowerCase();
  return s == '1' || s == 'true';
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  final String s = value.toString();
  return s.isEmpty ? null : s;
}

DateTime asDate(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(asInt(value));

DateTime? asDateOrNull(Object? value) =>
    value == null ? null : DateTime.fromMillisecondsSinceEpoch(asInt(value));

int b(bool value) => value ? 1 : 0;

// --- Wallet --------------------------------------------------------------

WalletEntity walletFromMap(Map<String, Object?> m) => WalletEntity(
      id: m['id']! as String,
      name: m['name']! as String,
      iconCode: asInt(m['icon_code']),
      colorValue: asInt(m['color_value']),
      currencyCode: (m['currency_code'] as String?) ?? 'EUR',
      initialBalanceCents: asInt(m['initial_balance_cents']),
      isDefault: asBool(m['is_default']),
      isArchived: asBool(m['is_archived']),
      sortOrder: asInt(m['sort_order']),
      createdAt: asDate(m['created_at']),
      updatedAt: asDate(m['updated_at']),
    );

extension WalletMapper on WalletEntity {
  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'icon_code': iconCode,
        'color_value': colorValue,
        'currency_code': currencyCode,
        'initial_balance_cents': initialBalanceCents,
        'is_default': b(isDefault),
        'is_archived': b(isArchived),
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

// --- Category ------------------------------------------------------------

CategoryEntity categoryFromMap(Map<String, Object?> m) => CategoryEntity(
      id: m['id']! as String,
      name: m['name']! as String,
      iconCode: asInt(m['icon_code']),
      colorValue: asInt(m['color_value']),
      type: TransactionType.fromDb((m['type'] as String?) ?? 'expense'),
      isDeleted: asBool(m['is_deleted']),
      isSystem: asBool(m['is_system']),
      sortOrder: asInt(m['sort_order']),
      createdAt: asDate(m['created_at']),
      updatedAt: asDate(m['updated_at']),
    );

extension CategoryMapper on CategoryEntity {
  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'icon_code': iconCode,
        'color_value': colorValue,
        'type': type.dbValue,
        'is_deleted': b(isDeleted),
        'is_system': b(isSystem),
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

// --- Transaction ---------------------------------------------------------

TransactionEntity transactionFromMap(Map<String, Object?> m) =>
    TransactionEntity(
      id: m['id']! as String,
      walletId: m['wallet_id']! as String,
      categoryId: asStringOrNull(m['category_id']),
      type: TransactionType.fromDb((m['type'] as String?) ?? 'expense'),
      amountCents: asInt(m['amount_cents']),
      note: asStringOrNull(m['note']),
      occurredAt: asDate(m['occurred_at']),
      transferWalletId: asStringOrNull(m['transfer_wallet_id']),
      recurringRuleId: asStringOrNull(m['recurring_rule_id']),
      isDeleted: asBool(m['is_deleted']),
      createdAt: asDate(m['created_at']),
      updatedAt: asDate(m['updated_at']),
    );

extension TransactionMapper on TransactionEntity {
  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'wallet_id': walletId,
        'category_id': categoryId,
        'type': type.dbValue,
        'amount_cents': amountCents,
        'note': note,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'transfer_wallet_id': transferWalletId,
        'recurring_rule_id': recurringRuleId,
        'is_deleted': b(isDeleted),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

/// Construye la vista enriquecida a partir de la fila del JOIN del DAO.
TransactionView transactionViewFromJoin(Map<String, Object?> m) =>
    TransactionView(
      transaction: transactionFromMap(m),
      walletName: (m['wallet_name'] as String?) ?? 'Cartera',
      walletColor: asInt(m['wallet_color']),
      categoryName: asStringOrNull(m['category_name']),
      categoryIconCode:
          m['category_icon'] == null ? null : asInt(m['category_icon']),
      categoryColor:
          m['category_color'] == null ? null : asInt(m['category_color']),
      transferWalletName: asStringOrNull(m['transfer_wallet_name']),
    );

// --- Budget --------------------------------------------------------------

BudgetEntity budgetFromMap(Map<String, Object?> m) => BudgetEntity(
      id: m['id']! as String,
      categoryId: asStringOrNull(m['category_id']),
      monthKey: asStringOrNull(m['month_key']),
      limitCents: asInt(m['limit_cents']),
      isDeleted: asBool(m['is_deleted']),
      createdAt: asDate(m['created_at']),
      updatedAt: asDate(m['updated_at']),
    );

extension BudgetMapper on BudgetEntity {
  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'category_id': categoryId,
        'month_key': monthKey,
        'limit_cents': limitCents,
        'is_deleted': b(isDeleted),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

// --- Recurring rule ------------------------------------------------------

RecurringRuleEntity recurringFromMap(Map<String, Object?> m) =>
    RecurringRuleEntity(
      id: m['id']! as String,
      walletId: m['wallet_id']! as String,
      categoryId: asStringOrNull(m['category_id']),
      type: TransactionType.fromDb((m['type'] as String?) ?? 'expense'),
      amountCents: asInt(m['amount_cents']),
      note: asStringOrNull(m['note']),
      frequency:
          RecurrenceFrequency.fromDb((m['frequency'] as String?) ?? 'monthly'),
      intervalCount: asInt(m['interval_count'], fallback: 1),
      nextRunAt: asDate(m['next_run_at']),
      endAt: asDateOrNull(m['end_at']),
      lastRunAt: asDateOrNull(m['last_run_at']),
      isActive: asBool(m['is_active'], fallback: true),
      isDeleted: asBool(m['is_deleted']),
      createdAt: asDate(m['created_at']),
      updatedAt: asDate(m['updated_at']),
    );

extension RecurringMapper on RecurringRuleEntity {
  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'wallet_id': walletId,
        'category_id': categoryId,
        'type': type.dbValue,
        'amount_cents': amountCents,
        'note': note,
        'frequency': frequency.dbValue,
        'interval_count': intervalCount,
        'next_run_at': nextRunAt.millisecondsSinceEpoch,
        'end_at': endAt?.millisecondsSinceEpoch,
        'last_run_at': lastRunAt?.millisecondsSinceEpoch,
        'is_active': b(isActive),
        'is_deleted': b(isDeleted),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}
