import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Carga la fuente china solo cuando hace falta.
///
/// ### Por qué hace falta cargarla
///
/// Archivo no tiene un solo glifo chino. En web el motor de Flutter lo
/// resolvería descargando una fuente de reserva de `fonts.gstatic.com`, pero
/// esta app lo tiene **prohibido por la política de seguridad** (`connect-src
/// 'self'`), que es lo que garantiza que no habla con nadie. Sin una fuente
/// empaquetada, cada carácter chino saldría como un rectángulo vacío.
///
/// ### Por qué solo cuando hace falta
///
/// Son 8,3 MB. Antes se pedían siempre a los tres segundos de abrir la app, y
/// en web CanvasKit procesa la fuente en el hilo principal: la app se quedaba
/// congelada un momento justo cuando se empezaba a usar, también para quien
/// no ha escrito nunca un carácter chino. Ahora se carga en dos casos:
///
///  * al abrir la bóveda, si algún texto guardado tiene caracteres chinos
///    ([ensureLoadedFor]);
///  * al teclearlos en un campo de texto libre ([CjkFontTrigger]).
///
/// Flutter rehace el layout cuando la fuente llega, así que el texto aparece
/// en cuanto está lista.
///
/// La interfaz está en español; esto no la traduce. Lo que permite es
/// ESCRIBIR en chino: el nombre de una categoría, el concepto de un gasto o
/// una nota.
abstract final class CjkFontLoader {
  /// Nombre de la familia. Debe coincidir con el que use
  /// `fontFamilyFallback` en el tema.
  static const String family = 'NotoSansSC';

  static const String _assetPath = 'assets/fonts/NotoSansSC-Regular.otf';

  static Future<void>? _pending;
  static bool _loaded = false;

  /// `true` cuando los glifos chinos ya se pueden pintar.
  static bool get isLoaded => _loaded;

  /// `true` si [text] tiene caracteres que cubre esta fuente: ideogramas
  /// CJK (también las extensiones), kana, puntuación CJK y formas de ancho
  /// completo.
  static bool containsCjk(String text) {
    for (final int rune in text.runes) {
      if ((rune >= 0x3000 && rune <= 0x9FFF) ||
          (rune >= 0xF900 && rune <= 0xFAFF) ||
          (rune >= 0xFF00 && rune <= 0xFFEF) ||
          (rune >= 0x20000 && rune <= 0x2FA1F)) {
        return true;
      }
    }
    return false;
  }

  /// Carga la fuente si alguno de [texts] la necesita.
  static Future<void> ensureLoadedFor(Iterable<String?> texts) {
    if (_loaded) return Future<void>.value();
    for (final String? text in texts) {
      if (text != null && containsCjk(text)) return ensureLoaded();
    }
    return Future<void>.value();
  }

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

/// Pide la fuente china en cuanto se teclea el primer carácter chino.
///
/// Va en los campos de texto libre (nombres, conceptos y notas). No altera lo
/// escrito: solo mira. El método de entrada chino entrega el texto ya
/// compuesto por aquí, así que también cubre lo que no llega tecla a tecla.
class CjkFontTrigger extends TextInputFormatter {
  const CjkFontTrigger();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!CjkFontLoader.isLoaded && CjkFontLoader.containsCjk(newValue.text)) {
      unawaited(CjkFontLoader.ensureLoaded());
    }
    return newValue;
  }
}
