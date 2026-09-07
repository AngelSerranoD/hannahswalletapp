import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Carga la fuente china en segundo plano.
///
/// ### Por qué hace falta cargarla, y por qué no en el arranque
///
/// Roboto no tiene un solo glifo chino. Normalmente el motor de Flutter lo
/// resolvería descargando una fuente de reserva de `fonts.gstatic.com`, pero
/// esta app lo tiene **prohibido por la política de seguridad** (`connect-src
/// 'self'`), que es lo que garantiza que no habla con nadie. Sin una fuente
/// empaquetada, cada carácter chino saldría como un rectángulo vacío.
///
/// La fuente completa son 8,3 MB. Declararla en la sección `fonts:` del
/// pubspec haría que se descargase SIEMPRE al abrir la app, incluso para quien
/// solo escribe en español. Por eso va como asset suelto y se carga aquí:
/// después del primer frame, sin bloquear nada. Flutter rehace el layout solo
/// cuando la fuente llega, así que el texto chino aparece en cuanto está
/// lista.
///
/// La interfaz de la app está en español; esto no la traduce. Lo que permite
/// es ESCRIBIR en chino: el nombre de una categoría, el concepto de un gasto o
/// una nota. Sin esta fuente, esos textos se guardarían bien pero se verían
/// como rectángulos vacíos.
abstract final class CjkFontLoader {
  /// Nombre de la familia. Debe coincidir con el que use
  /// `fontFamilyFallback` en el tema.
  static const String family = 'NotoSansSC';

  static const String _assetPath = 'assets/fonts/NotoSansSC-Regular.otf';

  static Future<void>? _pending;
  static bool _loaded = false;

  /// `true` cuando los glifos chinos ya se pueden pintar.
  static bool get isLoaded => _loaded;

  /// Arranca la carga si no se ha hecho ya. Idempotente y no bloqueante.
  ///
  /// Devuelve el mismo future en llamadas simultáneas: sin eso, dos pantallas
  /// que la pidan a la vez descargarían 8 MB dos veces.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  static Future<void> _load() async {
    try {
      final ByteData data = await rootBundle.load(_assetPath);
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(data));
      await loader.load();
      _loaded = true;
    } catch (error, stack) {
      // Que falte la fuente no puede tumbar la app: se degrada a que el texto
      // chino se vea como rectángulos, que es molesto pero no impide usarla.
      _loaded = false;
      debugPrint('No se pudo cargar la fuente china: $error\n$stack');
    }
  }

  /// Solo para pruebas: olvida lo cargado.
  @visibleForTesting
  static void resetForTest() {
    _loaded = false;
    _pending = null;
  }
}
