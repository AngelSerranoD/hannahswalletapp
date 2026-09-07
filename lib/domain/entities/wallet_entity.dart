import 'package:equatable/equatable.dart';

/// Una cartera o cuenta: efectivo, banco, tarjeta, hucha...
///
/// [initialBalanceCents] es el saldo que ya existia antes de empezar a usar la
/// app. Sin este campo, el usuario tendría que inventarse un ingreso ficticio
/// de "saldo inicial" que después ensuciaría las estadísticas de ingresos.
class WalletEntity extends Equatable {
  const WalletEntity({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.currencyCode,
    required this.initialBalanceCents,
    required this.createdAt,
    required this.updatedAt,
    this.isDefault = false,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int iconCode;
  final int colorValue;
  final String currencyCode;
  final int initialBalanceCents;
  final bool isDefault;
  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  WalletEntity copyWith({
    String? name,
    int? iconCode,
    int? colorValue,
    String? currencyCode,
    int? initialBalanceCents,
    bool? isDefault,
    bool? isArchived,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return WalletEntity(
      id: id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      currencyCode: currencyCode ?? this.currencyCode,
      initialBalanceCents: initialBalanceCents ?? this.initialBalanceCents,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        iconCode,
        colorValue,
        currencyCode,
        initialBalanceCents,
        isDefault,
        isArchived,
        sortOrder,
        updatedAt,
      ];
}

/// Cartera con su saldo ya calculado por SQL.
class WalletWithBalance extends Equatable {
  const WalletWithBalance({required this.wallet, required this.balanceCents});

  final WalletEntity wallet;
  final int balanceCents;

  @override
  List<Object?> get props => <Object?>[wallet, balanceCents];
}
