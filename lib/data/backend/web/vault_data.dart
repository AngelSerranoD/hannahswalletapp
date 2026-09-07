import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/budget_entity.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/recurring_rule_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/entities/wallet_entity.dart';
import '../../models/entity_mappers.dart';

/// Contenido descifrado de la bóveda, en memoria.
///
/// Es el equivalente web de la base SQLite: las mismas cinco tablas mas los
/// ajustes. Se guardan en mapas por `id` y no en listas para que actualizar o
/// borrar un registro sea directo en vez de un recorrido lineal.
///
/// DETALLE IMPORTANTE: [toBackupMap] produce EXACTAMENTE la misma estructura
/// que exporta la versión nativa. Eso hace que el JSON de copia sea
/// intercambiable entre el móvil y la PWA sin conversion alguna, y además
/// significa que la bóveda cifrada no es mas que ese mismo JSON metido en un
/// sobre AES-GCM.
class VaultData {
  VaultData({
    Map<String, WalletEntity>? wallets,
    Map<String, CategoryEntity>? categories,
    Map<String, TransactionEntity>? transactions,
    Map<String, BudgetEntity>? budgets,
    Map<String, RecurringRuleEntity>? recurring,
    Map<String, String>? settings,
  })  : wallets = wallets ?? <String, WalletEntity>{},
        categories = categories ?? <String, CategoryEntity>{},
        transactions = transactions ?? <String, TransactionEntity>{},
        budgets = budgets ?? <String, BudgetEntity>{},
        recurring = recurring ?? <String, RecurringRuleEntity>{},
        settings = settings ?? <String, String>{};

  /// Reconstruye la bóveda desde el JSON de copia.
  ///
  /// Cada fila se envuelve en un try: una entrada corrupta o de una versión
  /// futura se descarta en silencio en lugar de impedir el acceso a TODO lo
  /// demas. En una app sin servidor, perder un movimiento es molesto; no poder
  /// abrir la aplicación es catastrofico.
  factory VaultData.fromBackupMap(Map<String, dynamic> data) {
    final VaultData vault = VaultData();

    void load<T>(
      String key,
      T Function(Map<String, Object?>) parse,
      void Function(T) add,
    ) {
      final Object? rows = data[key];
      if (rows is! List) return;
      for (final Object? raw in rows) {
        if (raw is! Map) continue;
        try {
          add(parse(<String, Object?>{
            for (final MapEntry<dynamic, dynamic> e in raw.entries)
              e.key.toString(): e.value,
          }));
        } catch (_) {
          continue;
        }
      }
    }

    load<WalletEntity>('wallets', walletFromMap,
        (WalletEntity w) => vault.wallets[w.id] = w);
    load<CategoryEntity>('categories', categoryFromMap,
        (CategoryEntity c) => vault.categories[c.id] = c);
    load<RecurringRuleEntity>('recurring_rules', recurringFromMap,
        (RecurringRuleEntity r) => vault.recurring[r.id] = r);
    load<TransactionEntity>('transactions', transactionFromMap,
        (TransactionEntity t) => vault.transactions[t.id] = t);
    load<BudgetEntity>('budgets', budgetFromMap,
        (BudgetEntity b) => vault.budgets[b.id] = b);

    final Object? settings = data['app_settings'];
    if (settings is List) {
      for (final Object? raw in settings) {
        if (raw is! Map) continue;
        final Object? key = raw['key'];
        final Object? value = raw['value'];
        if (key != null && value != null) {
          vault.settings[key.toString()] = value.toString();
        }
      }
    }

    return vault;
  }

  /// Bóveda recien creada, con las mismas categorías y cartera que siembra la
  /// versión nativa. Se reproduce aquí para que la experiencia de estreno sea
  /// identica en las dos plataformas.
  factory VaultData.seeded() {
    final VaultData vault = VaultData();
    final DateTime now = DateTime.now();

    final WalletEntity wallet = WalletEntity(
      id: IdGenerator.newId(),
      name: 'Principal',
      iconCode: Icons.account_balance_wallet_outlined.codePoint,
      colorValue: AppColors.primary.toARGB32(),
      currencyCode: 'EUR',
      initialBalanceCents: 0,
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    );
    vault.wallets[wallet.id] = wallet;

    void seed(String name, IconData icon, int color, TransactionType type, int order) {
      final CategoryEntity c = CategoryEntity(
        id: IdGenerator.newId(),
        name: name,
        iconCode: icon.codePoint,
        colorValue: color,
        type: type,
        isSystem: true,
        sortOrder: order,
        createdAt: now,
        updatedAt: now,
      );
      vault.categories[c.id] = c;
    }

    const List<(String, IconData, int)> expenses = <(String, IconData, int)>[
      ('Alimentación', Icons.shopping_cart_outlined, 0xFF0A3323),
      ('Restaurantes', Icons.restaurant_outlined, 0xFFD3968C),
      ('Transporte', Icons.directions_bus_outlined, 0xFF105666),
      ('Vivienda', Icons.home_outlined, 0xFF839958),
      ('Suministros', Icons.bolt_outlined, 0xFF4D6B40),
      ('Salud', Icons.medical_services_outlined, 0xFF789D98),
      ('Ocio', Icons.movie_outlined, 0xFF0A3323),
      ('Compras', Icons.checkroom_outlined, 0xFFD3968C),
      ('Suscripciones', Icons.subscriptions_outlined, 0xFF105666),
      ('Educación', Icons.school_outlined, 0xFF839958),
      ('Otros gastos', Icons.more_horiz_outlined, 0xFF4D6B40),
    ];
    const List<(String, IconData, int)> incomes = <(String, IconData, int)>[
      ('Nómina', Icons.work_outline, 0xFF789D98),
      ('Autónomo', Icons.payments_outlined, 0xFF0A3323),
      ('Inversiones', Icons.trending_up_outlined, 0xFFD3968C),
      ('Regalos', Icons.card_giftcard_outlined, 0xFF105666),
      ('Otros ingresos', Icons.more_horiz_outlined, 0xFF839958),
    ];

    for (int i = 0; i < expenses.length; i++) {
      seed(expenses[i].$1, expenses[i].$2, expenses[i].$3,
          TransactionType.expense, i);
    }
    for (int i = 0; i < incomes.length; i++) {
      seed(incomes[i].$1, incomes[i].$2, incomes[i].$3,
          TransactionType.income, i);
    }

    vault.settings.addAll(<String, String>{
      AppConstants.kCurrencyCode: 'EUR',
      // `false`, igual que la siembra nativa. Este ajuste gobierna el bloqueo
      // de PANTALLA, que solo existe en móvil; sembrarlo a `true` desde la web
      // dejaba un dato incoherente que, al importar el backup en el móvil,
      // activaba un bloqueo sin PIN configurado.
      AppConstants.kLockEnabled: 'false',
      AppConstants.kBiometricEnabled: 'false',
      AppConstants.kMascotEnabled: 'true',
      AppConstants.kOnboardingDone: 'false',
    });

    return vault;
  }

  final Map<String, WalletEntity> wallets;
  final Map<String, CategoryEntity> categories;
  final Map<String, TransactionEntity> transactions;
  final Map<String, BudgetEntity> budgets;
  final Map<String, RecurringRuleEntity> recurring;
  final Map<String, String> settings;

  /// Serializa al formato de copia de seguridad, compatible con la versión
  /// nativa fila por fila.
  Map<String, dynamic> toBackupMap() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return <String, dynamic>{
      'wallets': wallets.values.map((WalletEntity w) => w.toMap()).toList(),
      'categories':
          categories.values.map((CategoryEntity c) => c.toMap()).toList(),
      'recurring_rules':
          recurring.values.map((RecurringRuleEntity r) => r.toMap()).toList(),
      'transactions': transactions.values
          .map((TransactionEntity t) => t.toMap())
          .toList(),
      'budgets': budgets.values.map((BudgetEntity b) => b.toMap()).toList(),
      'app_settings': settings.entries
          .map((MapEntry<String, String> e) => <String, Object?>{
                'key': e.key,
                'value': e.value,
                'updated_at': now,
              })
          .toList(),
    };
  }

  void clear() {
    wallets.clear();
    categories.clear();
    transactions.clear();
    budgets.clear();
    recurring.clear();
    settings.clear();
  }

  /// Vuelca el contenido de [other] encima del actual.
  void replaceWith(VaultData other) {
    clear();
    wallets.addAll(other.wallets);
    categories.addAll(other.categories);
    transactions.addAll(other.transactions);
    budgets.addAll(other.budgets);
    recurring.addAll(other.recurring);
    settings.addAll(other.settings);
  }

  /// Fusiona [other] sobre el actual: lo que comparte `id` se sobreescribe.
  void mergeFrom(VaultData other) {
    wallets.addAll(other.wallets);
    categories.addAll(other.categories);
    transactions.addAll(other.transactions);
    budgets.addAll(other.budgets);
    recurring.addAll(other.recurring);
    settings.addAll(other.settings);
  }

  Map<String, int> get counts => <String, int>{
        'wallets': wallets.length,
        'categories': categories.length,
        'recurring_rules': recurring.length,
        'transactions': transactions.length,
        'budgets': budgets.length,
        'app_settings': settings.length,
      };
}
