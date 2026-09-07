import 'package:equatable/equatable.dart';

/// Naturaleza de un movimiento.
enum TransactionType {
  expense('expense', 'Gasto'),
  income('income', 'Ingreso'),

  /// Traspaso entre dos carteras propias. No altera el patrimonio total.
  transfer('transfer', 'Traspaso');

  const TransactionType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static TransactionType fromDb(String value) => values.firstWhere(
        (TransactionType t) => t.dbValue == value,
        orElse: () => TransactionType.expense,
      );

  /// Signo con el que el movimiento afecta a la cartera de origen.
  int get sign => this == TransactionType.income ? 1 : -1;
}

/// Un movimiento del libro de cuentas.
///
/// [amountCents] es SIEMPRE positivo: el signo lo aporta [type]. Guardar
/// importes negativos para los gastos parece comodo hasta que hay que sumar
/// "cuanto he gastado" y todas las consultas se llenan de `ABS()`.
class TransactionEntity extends Equatable {
  const TransactionEntity({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amountCents,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.note,
    this.transferWalletId,
    this.recurringRuleId,
    this.isDeleted = false,
  });

  final String id;
  final String walletId;
  final String? categoryId;
  final TransactionType type;
  final int amountCents;
  final String? note;
  final DateTime occurredAt;
  final String? transferWalletId;
  final String? recurringRuleId;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Importe con signo, para sumar saldos.
  int get signedCents => amountCents * type.sign;

  bool get isTransfer => type == TransactionType.transfer;

  TransactionEntity copyWith({
    String? walletId,
    String? categoryId,
    bool clearCategory = false,
    TransactionType? type,
    int? amountCents,
    String? note,
    bool clearNote = false,
    DateTime? occurredAt,
    String? transferWalletId,
    bool clearTransferWallet = false,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return TransactionEntity(
      id: id,
      walletId: walletId ?? this.walletId,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      note: clearNote ? null : (note ?? this.note),
      occurredAt: occurredAt ?? this.occurredAt,
      transferWalletId:
          clearTransferWallet ? null : (transferWalletId ?? this.transferWalletId),
      recurringRuleId: recurringRuleId,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        walletId,
        categoryId,
        type,
        amountCents,
        note,
        occurredAt,
        transferWalletId,
        recurringRuleId,
        isDeleted,
        updatedAt,
      ];
}

/// Movimiento ya resuelto con los datos de su categoría y cartera.
///
/// Lo devuelve el DAO con un único JOIN. La alternativa (traer el movimiento y
/// buscar después su categoría) provocaria una consulta por fila: el clasico
/// N+1 que hunde el scroll del dashboard en cuanto hay unos cientos de gastos.
class TransactionView extends Equatable {
  const TransactionView({
    required this.transaction,
    required this.walletName,
    required this.walletColor,
    this.categoryName,
    this.categoryIconCode,
    this.categoryColor,
    this.transferWalletName,
  });

  final TransactionEntity transaction;
  final String walletName;
  final int walletColor;
  final String? categoryName;
  final int? categoryIconCode;
  final int? categoryColor;
  final String? transferWalletName;

  String get displayTitle {
    final String? note = transaction.note?.trim();
    if (note != null && note.isNotEmpty) return note;
    if (transaction.isTransfer) {
      return 'Traspaso a ${transferWalletName ?? 'otra cartera'}';
    }
    return categoryName ?? 'Sin categoría';
  }

  String get displaySubtitle {
    if (transaction.isTransfer) return walletName;
    final String? note = transaction.note?.trim();
    if (note != null && note.isNotEmpty) {
      return '${categoryName ?? 'Sin categoria'} · $walletName';
    }
    return walletName;
  }

  @override
  List<Object?> get props => <Object?>[
        transaction,
        walletName,
        walletColor,
        categoryName,
        categoryIconCode,
        categoryColor,
        transferWalletName,
      ];
}
