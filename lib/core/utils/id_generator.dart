import 'dart:math';

/// Generador de identificadores UUID v4.
///
/// Se implementa aquí en lugar de tirar del paquete `uuid` porque son treinta
/// lineas y ahorra una dependencia en el nucleo de la app.
///
/// Se usa [Random.secure] y no `Random()`: dos instalaciones distintas de la
/// app podrían sembrar el generador débil con la misma marca de tiempo, y al
/// fusionar sus backups los ids chocarian.
abstract final class IdGenerator {
  static final Random _rng = Random.secure();
  static const String _hex = '0123456789abcdef';

  /// UUID v4 canonico: 8-4-4-4-12 con los bits de versión y variante fijados.
  static String newId() {
    final List<int> bytes = List<int>.generate(16, (_) => _rng.nextInt(256));

    // Versión 4 en el nibble alto del byte 6.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Variante RFC 4122 en los dos bits altos del byte 8.
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final StringBuffer out = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) out.write('-');
      out
        ..write(_hex[(bytes[i] >> 4) & 0x0F])
        ..write(_hex[bytes[i] & 0x0F]);
    }
    return out.toString();
  }
}
