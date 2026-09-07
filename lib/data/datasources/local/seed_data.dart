import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/id_generator.dart';

/// Contenido inicial de una base recien creada.
///
/// Una app de gastos vacia es inutilizable: obliga a inventarse diez
/// categorías antes de poder anotar el primer cafe. Se siembran las categorías
/// habituales (marcadas `is_system = 1`) y una cartera por defecto.
///
/// `is_system` no impide editarlas ni borrarlas; solo sirve para saber cuales
/// vinieron de fabrica y poder reofrecerlas si el usuario las borra todas.
abstract final class SeedData {
  static Future<void> populate(Transaction txn) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    await txn.insert('wallets', <String, Object?>{
      'id': IdGenerator.newId(),
      'name': 'Principal',
      'icon_code': Icons.account_balance_wallet_outlined.codePoint,
      'color_value': AppColors.primary.toARGB32(),
      'currency_code': 'EUR',
      'initial_balance_cents': 0,
      'is_default': 1,
      'is_archived': 0,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });

    int order = 0;
    for (final _SeedCategory c in _expenseCategories) {
      await _insertCategory(txn, c, 'expense', order++, now);
    }
    order = 0;
    for (final _SeedCategory c in _incomeCategories) {
      await _insertCategory(txn, c, 'income', order++, now);
    }

    // Preferencias de arranque.
    for (final MapEntry<String, String> e in <String, String>{
      AppConstants.kCurrencyCode: 'EUR',
      AppConstants.kLockEnabled: 'false',
      AppConstants.kBiometricEnabled: 'false',
      AppConstants.kMascotEnabled: 'true',
      AppConstants.kOnboardingDone: 'false',
    }.entries) {
      await txn.insert('app_settings', <String, Object?>{
        'key': e.key,
        'value': e.value,
        'updated_at': now,
      });
    }
  }

  static Future<void> _insertCategory(
    Transaction txn,
    _SeedCategory c,
    String type,
    int order,
    int now,
  ) {
    return txn.insert('categories', <String, Object?>{
      'id': IdGenerator.newId(),
      'name': c.name,
      'icon_code': c.icon.codePoint,
      'color_value': c.color,
      'type': type,
      'is_deleted': 0,
      'is_system': 1,
      'sort_order': order,
      'created_at': now,
      'updated_at': now,
    });
  }

  static const List<_SeedCategory> _expenseCategories = <_SeedCategory>[
    _SeedCategory('Alimentación', Icons.shopping_cart_outlined, 0xFF0A3323),
    _SeedCategory('Restaurantes', Icons.restaurant_outlined, 0xFFD3968C),
    _SeedCategory('Transporte', Icons.directions_bus_outlined, 0xFF105666),
    _SeedCategory('Vivienda', Icons.home_outlined, 0xFF839958),
    _SeedCategory('Suministros', Icons.bolt_outlined, 0xFF4D6B40),
    _SeedCategory('Salud', Icons.medical_services_outlined, 0xFF789D98),
    _SeedCategory('Ocio', Icons.movie_outlined, 0xFF0A3323),
    _SeedCategory('Compras', Icons.checkroom_outlined, 0xFFD3968C),
    _SeedCategory('Suscripciones', Icons.subscriptions_outlined, 0xFF105666),
    _SeedCategory('Educación', Icons.school_outlined, 0xFF839958),
    _SeedCategory('Otros gastos', Icons.more_horiz_outlined, 0xFF4D6B40),
  ];

  static const List<_SeedCategory> _incomeCategories = <_SeedCategory>[
    _SeedCategory('Nómina', Icons.work_outline, 0xFF789D98),
    _SeedCategory('Autónomo', Icons.payments_outlined, 0xFF0A3323),
    _SeedCategory('Inversiones', Icons.trending_up_outlined, 0xFFD3968C),
    _SeedCategory('Regalos', Icons.card_giftcard_outlined, 0xFF105666),
    _SeedCategory('Otros ingresos', Icons.more_horiz_outlined, 0xFF839958),
  ];
}

class _SeedCategory {
  const _SeedCategory(this.name, this.icon, this.color);
  final String name;
  final IconData icon;
  final int color;
}
