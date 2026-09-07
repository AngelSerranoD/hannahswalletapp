import 'package:intl/intl.dart';

/// Utilidades monetarias.
///
/// REGLA DE ORO DE LA APP: el dinero viaja SIEMPRE en enteros de la unidad
/// minima (centimos). Nunca en `double`. Sumar 0.1 + 0.2 en coma flotante da
/// 0.30000000000000004, y en una app de finanzas eso acaba en un saldo que no
/// cuadra por un centimo después de unos cientos de movimientos.
///
/// Solo se convierte a `double` en el último milimetro: al pintar una gráfica.
abstract final class Money {
  /// Formateadores ya construidos, reutilizados por clave.
  ///
  /// `NumberFormat.currency` no es barato: analiza el patron del locale y monta
  /// sus tablas de simbolos en cada llamada. La lista de movimientos pinta un
  /// importe por fila y el saldo se reformatea en cada fotograma de su
  /// animacion, asi que se construian decenas por segundo y se tiraban acto
  /// seguido. Guardarlos deja el coste en uno por moneda.
  static final Map<String, NumberFormat> _cache = <String, NumberFormat>{};

  static NumberFormat _formatter(String key, NumberFormat Function() build) =>
      _cache[key] ??= build();
  /// Convierte lo que escribe el usuario ("12,50", "12.5", "1.234,56") a
  /// centimos. Devuelve `null` si el texto no es un importe valido.
  static int? parseToCents(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[\s  ]'), '');
    s = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (s.isEmpty) return null;

    final bool negative = s.startsWith('-');
    if (negative) s = s.substring(1);
    s = s.replaceAll('-', '');
    if (s.isEmpty) return null;

    final int lastComma = s.lastIndexOf(',');
    final int lastDot = s.lastIndexOf('.');

    if (lastComma == -1 && lastDot == -1) {
      // Entero puro, nada que normalizar.
    } else if (lastComma != -1 && lastDot != -1) {
      // Aparecen los dos: el ULTIMO es el decimal y el otro son millares.
      // Cubre a la vez "1.234,56" (espanol) y "1,234.56" (ingles).
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '');
        s = '${s.substring(0, s.lastIndexOf(','))}.'
            '${s.substring(s.lastIndexOf(',') + 1)}';
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastComma != -1) {
      // Solo coma: en es_ES la coma es SIEMPRE el decimal. Es lo que produce
      // el teclado numerico del móvil en espanol, así que "1,234" son 1,23 EUR
      // (redondeado al centimo), no mil doscientos treinta y cuatro.
      s = '${s.substring(0, lastComma)}.${s.substring(lastComma + 1)}'
          .replaceAll(',', '');
    } else {
      // Solo punto. Aquí esta la ambiguedad de verdad: en espanol el punto es
      // separador de millares ("1.234" son mil doscientos treinta y cuatro),
      // pero muchos teclados fisicos y configuraciones dan punto decimal
      // ("12.50" son doce con cincuenta).
      //
      // Se resuelve por la longitud del grupo final: exactamente tres cifras
      // detras del punto es el patron inequivoco de los millares; una o dos,
      // el de los centimos. Cuatro o mas no es ninguna de las dos cosas y se
      // deja como decimal, que es lo que menos sorprende.
      final String tail = s.substring(lastDot + 1);
      if (tail.length == 3 && !tail.contains('.')) {
        s = s.replaceAll('.', '');
      }
    }

    final double? value = double.tryParse(s);
    if (value == null || value.isNaN || value.isInfinite) return null;

    final int cents = (value * 100).round();
    return negative ? -cents : cents;
  }

  /// Centimos -> texto editable en el campo de importe, sin simbolo.
  static String centsToPlainString(int cents, {String locale = 'es_ES'}) {
    return _formatter('plain:$locale', () => NumberFormat('0.00', locale))
        .format(cents / 100);
  }

  /// Centimos -> texto con simbolo de moneda, listo para pintar.
  static String format(
    int cents, {
    String currencyCode = 'EUR',
    String locale = 'es_ES',
    bool showSign = false,
  }) {
    final NumberFormat f = _formatter(
      'cur:$locale:$currencyCode',
      () => NumberFormat.currency(
        locale: locale,
        symbol: symbolFor(currencyCode),
        decimalDigits: 2,
      ),
    );
    final String body = f.format(cents.abs() / 100);
    if (cents < 0) return '-$body';
    if (showSign && cents > 0) return '+$body';
    return body;
  }

  /// Versión compacta para ejes de gráficas: 1,2 k / 3,4 M.
  static String formatCompact(
    int cents, {
    String currencyCode = 'EUR',
    String locale = 'es_ES',
  }) {
    final double units = cents / 100;
    final String symbol = symbolFor(currencyCode);
    final double abs = units.abs();
    if (abs >= 1000000) {
      return '${_formatter('c1:$locale', () => NumberFormat('0.#', locale)).format(units / 1000000)}M $symbol';
    }
    if (abs >= 1000) {
      return '${_formatter('c1:$locale', () => NumberFormat('0.#', locale)).format(units / 1000)}k $symbol';
    }
    return '${_formatter('c0:$locale', () => NumberFormat('0', locale)).format(units)} $symbol';
  }

  static String symbolFor(String currencyCode) {
    return switch (currencyCode.toUpperCase()) {
      'EUR' => '€',
      'USD' => r'$',
      'GBP' => '£',
      'JPY' => '¥',
      'CHF' => 'CHF',
      'MXN' => r'$',
      'ARS' => r'$',
      'COP' => r'$',
      'BRL' => r'R$',
      'MAD' => 'MAD',
      _ => currencyCode.toUpperCase(),
    };
  }

  /// Monedas ofrecidas en Ajustes. EUR primero: el icono de la app lleva euros.
  static const List<({String code, String label})> supportedCurrencies = [
    (code: 'EUR', label: 'Euro'),
    (code: 'USD', label: 'Dolar estadounidense'),
    (code: 'GBP', label: 'Libra esterlina'),
    (code: 'CHF', label: 'Franco suizo'),
    (code: 'MXN', label: 'Peso mexicano'),
    (code: 'ARS', label: 'Peso argentino'),
    (code: 'COP', label: 'Peso colombiano'),
    (code: 'BRL', label: 'Real brasileño'),
    (code: 'JPY', label: 'Yen japonés'),
    (code: 'MAD', label: 'Dirham marroquí'),
  ];
}
