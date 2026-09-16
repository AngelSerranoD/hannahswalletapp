import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/error/failures.dart';
import 'package:hannahswalletapp/data/models/entity_mappers.dart';
import 'package:hannahswalletapp/domain/entities/budget_entity.dart';
import 'package:hannahswalletapp/domain/entities/category_entity.dart';
import 'package:hannahswalletapp/domain/entities/transaction_entity.dart';
import 'package:hannahswalletapp/domain/services/budget_planner.dart';

/// Pruebas de las reglas de los límites con nombre y varias categorías.
///
/// Son las que deciden cuánto dinero se enseña como gastado y cuánto queda
/// libre. Un error aquí no rompe nada visible: simplemente la cifra no cuadra.
void main() {
  final DateTime t = DateTime(2026, 9, 1);
  const String sep = '2026-09';

  CategoryEntity cat(String id, String name, {int order = 0}) =>
      CategoryEntity(
        id: id,
        name: name,
        iconCode: 1,
        colorValue: 0xFF000000,
        type: TransactionType.expense,
        sortOrder: order,
        createdAt: t,
        updatedAt: t,
      );

  BudgetEntity budget(
    String id,
    int cents, {
    List<String> cats = const <String>[],
    String? month,
    String? name,
  }) =>
      BudgetEntity(
        id: id,
        name: name,
        categoryIds: cats,
        monthKey: month,
        limitCents: cents,
        createdAt: t,
        updatedAt: t,
      );

  final Map<String, CategoryEntity> cats = <String, CategoryEntity>{
    'cine': cat('cine', 'Cine', order: 2),
    'bares': cat('bares', 'Bares', order: 1),
    'super': cat('super', 'Supermercado', order: 0),
  };

  group('vigencia', () {
    test('el global del mes sustituye a la plantilla global', () {
      final List<BudgetEntity> result = BudgetPlanner.effectiveFor(
        <BudgetEntity>[budget('plantilla', 100000), budget('sep', 80000, month: sep)],
        sep,
      );
      expect(result.map((BudgetEntity b) => b.id), <String>['sep']);
    });

    test('un límite del mes quita la plantilla con la que comparte categoría', () {
      final List<BudgetEntity> result = BudgetPlanner.effectiveFor(
        <BudgetEntity>[
          budget('ocio', 20000, cats: <String>['cine', 'bares']),
          budget('comida', 30000, cats: <String>['super']),
          budget('cine-sep', 5000, cats: <String>['cine'], month: sep),
        ],
        sep,
      );
      // Conservar "ocio" contaría dos veces el gasto de cine.
      expect(
        result.map((BudgetEntity b) => b.id).toSet(),
        <String>{'cine-sep', 'comida'},
      );
    });

    test('los borrados no cuentan', () {
      final BudgetEntity borrado =
          budget('x', 1000).copyWith(isDeleted: true);
      expect(BudgetPlanner.effectiveFor(<BudgetEntity>[borrado], sep), isEmpty);
    });
  });

  group('consumo', () {
    final Map<String?, int> gasto = <String?, int>{
      'cine': 1200,
      'bares': 3000,
      'super': 8000,
      null: 500,
    };

    test('un límite suma solo sus categorías y el global lo suma todo', () {
      final List<BudgetProgress> result = BudgetPlanner.progress(
        budgets: <BudgetEntity>[
          budget('ocio', 20000, cats: <String>['cine', 'bares'], name: 'Ocio'),
          budget('total', 100000),
        ],
        categories: cats,
        spentByCategory: gasto,
        monthKey: sep,
      );

      expect(result.first.budget.id, 'total', reason: 'el global va primero');
      expect(result.first.spentCents, 12700);
      expect(result.last.spentCents, 4200);
      expect(result.last.displayName, 'Ocio');
      expect(result.last.categoryNames, 'Cine y Bares');
    });

    test('sin nombre, la tarjeta se titula con sus categorías', () {
      final BudgetProgress p = BudgetPlanner.progress(
        budgets: <BudgetEntity>[
          budget('b', 1000, cats: <String>['super', 'cine', 'bares']),
        ],
        categories: cats,
        spentByCategory: const <String?, int>{},
        monthKey: sep,
      ).single;
      expect(p.displayName, 'Supermercado, Cine y Bares');
      expect(p.iconCode, isNull, reason: 'varias categorías no tienen un icono');
    });

    test('conserva las categorías eliminadas', () {
      final Map<String, CategoryEntity> conBorrada = <String, CategoryEntity>{
        ...cats,
        'cine': cats['cine']!.copyWith(isDeleted: true),
      };
      final BudgetProgress p = BudgetPlanner.progress(
        budgets: <BudgetEntity>[budget('b', 1000, cats: <String>['cine'])],
        categories: conBorrada,
        spentByCategory: const <String?, int>{'cine': 700},
        monthKey: sep,
      ).single;
      expect(p.categories.single.name, 'Cine');
      expect(p.spentCents, 700);
    });
  });

  group('guardar', () {
    test('rechaza un límite de cero', () {
      expect(
        () => BudgetPlanner.prepareSave(
          budget('b', 0),
          existing: const <BudgetEntity>[],
          categories: cats,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('recorta el nombre, lo anula si queda vacío y quita repetidas', () {
      final BudgetEntity limpio = BudgetPlanner.prepareSave(
        budget('b', 100, cats: <String>['cine', 'cine', 'bares'], name: '   '),
        existing: const <BudgetEntity>[],
        categories: cats,
      );
      expect(limpio.name, isNull);
      expect(limpio.categoryIds, <String>['cine', 'bares']);

      final BudgetEntity conNombre = BudgetPlanner.prepareSave(
        budget('b', 100, cats: <String>['cine'], name: '  Ocio  '),
        existing: const <BudgetEntity>[],
        categories: cats,
      );
      expect(conNombre.name, 'Ocio');
    });

    test('un segundo total del mismo periodo actualiza el que había', () {
      final BudgetEntity result = BudgetPlanner.prepareSave(
        budget('nuevo', 90000),
        existing: <BudgetEntity>[budget('viejo', 50000)],
        categories: cats,
      );
      expect(result.id, 'viejo');
      expect(result.limitCents, 90000);
    });

    test('una categoría no puede estar en dos límites del mismo periodo', () {
      expect(
        () => BudgetPlanner.prepareSave(
          budget('nuevo', 100, cats: <String>['bares']),
          existing: <BudgetEntity>[
            budget('ocio', 100, cats: <String>['cine', 'bares'], name: 'Ocio'),
          ],
          categories: cats,
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (ValidationFailure f) => f.message,
            'message',
            allOf(contains('Bares'), contains('Ocio')),
          ),
        ),
      );
    });

    test('sí puede estar en la plantilla y en un límite puntual', () {
      expect(
        BudgetPlanner.prepareSave(
          budget('sep', 100, cats: <String>['cine'], month: sep),
          existing: <BudgetEntity>[budget('ocio', 100, cats: <String>['cine'])],
          categories: cats,
        ).id,
        'sep',
      );
    });

    test('editar un límite no choca consigo mismo', () {
      final BudgetEntity ocio = budget('ocio', 100, cats: <String>['cine']);
      expect(
        BudgetPlanner.prepareSave(
          ocio.copyWith(limitCents: 200),
          existing: <BudgetEntity>[ocio],
          categories: cats,
        ).limitCents,
        200,
      );
    });
  });

  group('formato guardado', () {
    test('lee filas antiguas de una sola categoría', () {
      final BudgetEntity b = budgetFromMap(<String, Object?>{
        'id': 'viejo',
        'category_id': 'cine',
        'month_key': null,
        'limit_cents': 5000,
        'is_deleted': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      expect(b.categoryIds, <String>['cine']);
      expect(b.name, isNull);
    });

    test('ida y vuelta con nombre y varias categorías', () {
      final BudgetEntity original =
          budget('b', 100, cats: <String>['cine', 'bares'], name: 'Ocio');
      final BudgetEntity leido = budgetFromMap(original.toMap());
      expect(leido.categoryIds, original.categoryIds);
      expect(leido.name, 'Ocio');
      expect(original.toMap().containsKey('category_id'), isFalse);
    });

    test('el global se guarda sin categorías y se lee como global', () {
      expect(budgetFromMap(budget('g', 100).toMap()).isGlobal, isTrue);
    });
  });

  test('el reparto cuenta límites, no categorías', () {
    final BudgetAllocation a = BudgetAllocation.from(
      BudgetPlanner.progress(
        budgets: <BudgetEntity>[
          budget('total', 100000),
          budget('ocio', 20000, cats: <String>['cine', 'bares']),
          budget('comida', 30000, cats: <String>['super']),
        ],
        categories: cats,
        spentByCategory: const <String?, int>{},
        monthKey: sep,
      ),
    );
    expect(a.limitCount, 2);
    expect(a.availableCents, 50000);
  });
}
