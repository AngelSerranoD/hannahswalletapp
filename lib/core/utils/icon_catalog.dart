import 'package:flutter/material.dart';

/// Catalogo cerrado de iconos para categorías y carteras.
///
/// Por que un catalogo y no `IconData(codePoint, fontFamily: 'MaterialIcons')`
/// construido al vuelo desde la base de datos: Flutter hace *tree-shaking* de
/// la fuente de iconos en compilacion release y solo conserva los glifos que
/// aparecen como constantes en el código. Un `IconData` dinamico rompe la
/// compilacion ("This application cannot tree shake icons fonts") u obliga a
/// pasar `--no-tree-shake-icons`, que engorda el APK con la fuente entera.
///
/// Aquí se guarda en la base el `codePoint` y se resuelve contra este mapa de
/// constantes, así que el tree-shaking sigue funcionando y el APK no crece.
abstract final class IconCatalog {
  static const IconData fallback = Icons.category_outlined;

  /// Iconos ofrecidos al crear o editar una categoría.
  static const List<IconData> categoryIcons = <IconData>[
    Icons.shopping_cart_outlined,
    Icons.restaurant_outlined,
    Icons.local_cafe_outlined,
    Icons.directions_bus_outlined,
    Icons.local_gas_station_outlined,
    Icons.home_outlined,
    Icons.bolt_outlined,
    Icons.wifi_outlined,
    Icons.phone_iphone_outlined,
    Icons.medical_services_outlined,
    Icons.fitness_center_outlined,
    Icons.school_outlined,
    Icons.checkroom_outlined,
    Icons.movie_outlined,
    Icons.sports_esports_outlined,
    Icons.flight_takeoff_outlined,
    Icons.pets_outlined,
    Icons.child_care_outlined,
    Icons.card_giftcard_outlined,
    Icons.subscriptions_outlined,
    Icons.build_outlined,
    Icons.local_hospital_outlined,
    Icons.spa_outlined,
    Icons.savings_outlined,
    Icons.payments_outlined,
    Icons.work_outline,
    Icons.trending_up_outlined,
    Icons.attach_money_outlined,
    Icons.redeem_outlined,
    Icons.receipt_long_outlined,
    Icons.more_horiz_outlined,
    Icons.category_outlined,
  ];

  /// Iconos ofrecidos al crear o editar una cartera.
  static const List<IconData> walletIcons = <IconData>[
    Icons.account_balance_wallet_outlined,
    Icons.payments_outlined,
    Icons.credit_card_outlined,
    Icons.account_balance_outlined,
    Icons.savings_outlined,
    Icons.currency_bitcoin_outlined,
    Icons.smartphone_outlined,
    Icons.lock_outlined,
  ];

  static final Map<int, IconData> _byCodePoint = <int, IconData>{
    for (final IconData i in categoryIcons) i.codePoint: i,
    for (final IconData i in walletIcons) i.codePoint: i,
  };

  /// Convierte el `codePoint` almacenado en un `IconData` constante.
  static IconData resolve(int codePoint) =>
      _byCodePoint[codePoint] ?? fallback;
}
