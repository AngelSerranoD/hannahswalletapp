import '../../../../core/error/failures.dart';
import '../../../../domain/entities/category_entity.dart';
import '../../../../domain/entities/transaction_entity.dart';
import '../../../../domain/repositories/repositories.dart';
import '../vault_data.dart';
import 'vault_session.dart';

class VaultCategoryRepository implements CategoryRepository {
  VaultCategoryRepository(this._session);

  final VaultSession _session;
  VaultData get _d => _session.data;

  @override
  Future<List<CategoryEntity>> getCategories({
    TransactionType? type,
    bool includeDeleted = false,
  }) async {
    final List<CategoryEntity> list = _d.categories.values
        .where((CategoryEntity c) =>
            (includeDeleted || !c.isDeleted) && (type == null || c.type == type))
        .toList()
      ..sort((CategoryEntity a, CategoryEntity b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0
            ? byOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  @override
  Future<CategoryEntity?> getById(String id) async => _d.categories[id];

  @override
  Future<void> create(CategoryEntity category) async {
    if (category.name.trim().isEmpty) {
      throw const ValidationFailure('La categoría necesita un nombre.');
    }
    _d.categories[category.id] = category;
    _session.touch();
  }

  @override
  Future<void> update(CategoryEntity category) async {
    if (category.name.trim().isEmpty) {
      throw const ValidationFailure('La categoría necesita un nombre.');
    }
    _d.categories[category.id] = category;
    _session.touch();
  }

  @override
  Future<void> softDelete(String id) async {
    final CategoryEntity? c = _d.categories[id];
    if (c == null) return;
    _d.categories[id] = c.copyWith(isDeleted: true);
    _session.touch();
  }

  @override
  Future<void> restore(String id) async {
    final CategoryEntity? c = _d.categories[id];
    if (c == null) return;
    _d.categories[id] = c.copyWith(isDeleted: false);
    _session.touch();
  }

  @override
  Future<int> usageCount(String id) async => _d.transactions.values
      .where((TransactionEntity t) => !t.isDeleted && t.categoryId == id)
      .length;

  @override
  Future<void> reorder(List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      final CategoryEntity? c = _d.categories[orderedIds[i]];
      if (c != null) _d.categories[c.id] = c.copyWith(sortOrder: i);
    }
    _session.touch();
  }
}
