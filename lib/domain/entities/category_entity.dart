import 'package:equatable/equatable.dart';

import 'transaction_entity.dart';

/// Categoría de gasto o de ingreso.
///
/// Sobre [isDeleted]: las categorías NUNCA se borran fisicamente. Si se
/// borrasen, todos los movimientos historicos que la usaban se quedarían sin
/// categoría y las estadísticas de años anteriores cambiarian de golpe. El
/// borrado lógico la retira de los selectores pero deja intacto el pasado.
class CategoryEntity extends Equatable {
  const CategoryEntity({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.isSystem = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int iconCode;
  final int colorValue;

  /// Solo `expense` o `income`; una categoría nunca es de traspaso.
  final TransactionType type;
  final bool isDeleted;
  final bool isSystem;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  CategoryEntity copyWith({
    String? name,
    int? iconCode,
    int? colorValue,
    TransactionType? type,
    bool? isDeleted,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return CategoryEntity(
      id: id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      type: type ?? this.type,
      isDeleted: isDeleted ?? this.isDeleted,
      isSystem: isSystem,
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
        type,
        isDeleted,
        isSystem,
        sortOrder,
        updatedAt,
      ];
}

/// Gasto agregado de una categoría en un periodo. Alimenta el donut y la lista
/// de la pantalla de estadísticas.
class CategorySpending extends Equatable {
  const CategorySpending({
    required this.categoryId,
    required this.categoryName,
    required this.iconCode,
    required this.colorValue,
    required this.totalCents,
    required this.entryCount,
  });

  final String? categoryId;
  final String categoryName;
  final int iconCode;
  final int colorValue;
  final int totalCents;
  final int entryCount;

  @override
  List<Object?> get props => <Object?>[
        categoryId,
        categoryName,
        iconCode,
        colorValue,
        totalCents,
        entryCount,
      ];
}
