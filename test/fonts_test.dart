import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/theme/app_theme.dart';

/// Reglas de tipografía.
///
/// Las dos familias se eligieron con un requisito por delante del parecido:
/// **licencia SIL OFL**, que permite incrustarlas en una app. Las anteriores
/// -Coolvetica y CandleScript- se descartaron porque sus licencias gratuitas
/// excluyen justamente este uso.
///
/// Lo que se comprueba aquí es lo que puede romperse sin avisar: que los
/// ficheros estén, que el tema use las familias correctas y que la caligráfica
/// cubra el español entero. Esto último es lo que hizo fracasar a la fuente
/// anterior: su demo solo traía 56 glifos y dibujaba su propio nombre en lugar
/// de los caracteres que le faltaban, así que "Estadísticas" salía en pantalla
/// como "EstadCandlescriptsticas".
void main() {
  group('tipografía', () {
    test('el tema usa Archivo de cuerpo y Pinyon Script de título', () {
      expect(AppTheme.bodyFont, 'Archivo');
      expect(AppTheme.titleFont, 'PinyonScript');
      expect(AppTheme.light().textTheme.bodyLarge, isNotNull);
    });

    test('titleStyle aplica la caligráfica a cualquier título', () {
      const TextStyle base = TextStyle(fontSize: 20);
      for (final String title in <String>[
        'Ajustes',
        'Estadísticas',   // tilde
        'Gestión',        // tilde
        'Año 2026',       // eñe y cifras
        'Exportar copia (JSON)',
      ]) {
        expect(
          AppTheme.titleStyle(title, base)?.fontFamily,
          AppTheme.titleFont,
          reason: title,
        );
      }
    });

    test('todos los estilos que reparte el tema llevan familia', () {
      // `ThemeData.fontFamily` solo se aplica a `theme.textTheme`: los estilos
      // que se pasan a mano a los temas de componentes se quedaban sin
      // familia y dependían de la fuente por defecto de cada plataforma. En
      // la web, además, el motor no tenía contra qué comprobar la «ó» de
      // «Crear bóveda», la daba por ausente y pedía una Noto a gstatic.
      final ThemeData theme = AppTheme.light();
      final TextTheme t = theme.textTheme;
      final Map<String, TextStyle?> estilos = <String, TextStyle?>{
        'filledButton':
            theme.filledButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
        'floatingActionButton':
            theme.floatingActionButtonTheme.extendedTextStyle,
        'snackBar': theme.snackBarTheme.contentTextStyle,
        'appBar': theme.appBarTheme.titleTextStyle,
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
      };
      for (final MapEntry<String, TextStyle?> e in estilos.entries) {
        expect(e.value?.fontFamily, AppTheme.bodyFont, reason: e.key);
        expect(e.value?.fontFamilyFallback, AppTheme.bodyFallback,
            reason: e.key);
      }
    });

    test('la web no pide nada fuera de su origen al arrancar', () {
      // Configuración del motor en la plantilla de arranque: CanvasKit y las
      // fuentes de reserva salen del propio build, nunca de gstatic.com. Y el
      // service worker propio se registra ahí: `flutter.js` ya no lo hace en
      // una instalación nueva.
      final String bootstrap =
          File('web/flutter_bootstrap.js').readAsStringSync();
      expect(bootstrap, contains('canvasKitBaseUrl: "canvaskit/"'));
      expect(bootstrap, contains('fontFallbackBaseUrl: "fuentes-reserva/"'));
      expect(bootstrap,
          contains('serviceWorker.register("flutter_service_worker.js")'));
      // Rutas relativas al build: ninguna URL absoluta.
      expect(bootstrap, isNot(contains('https://')));
      expect(bootstrap, isNot(contains('http://')));
    });

    test('los ficheros de fuente están en el proyecto', () {
      for (final String path in <String>[
        'assets/fonts/Archivo-Regular.ttf',
        'assets/fonts/Archivo-Medium.ttf',
        'assets/fonts/Archivo-Bold.ttf',
        'assets/fonts/PinyonScript-Regular.ttf',
        'assets/fonts/NotoSansSC-Regular.otf',
        'assets/fonts/web/NotoSansSymbols-Reserva.woff2',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('no quedan restos de las fuentes con licencia restrictiva', () {
      // Si alguna vuelve al proyecto, la app dejaría de poder publicarse sin
      // comprar licencias. Mejor que salte aquí que descubrirlo después.
      for (final String path in <String>[
        'assets/fonts/Coolvetica-Regular.otf',
        'assets/fonts/CandleScript-Demo.otf',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      // Se busca la DECLARACIÓN, no la palabra: el pubspec las menciona en un
      // comentario que explica por qué se descartaron, y esa nota conviene
      // conservarla para que nadie las reintroduzca sin saberlo.
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('family: Coolvetica')));
      expect(pubspec, isNot(contains('family: CandleScript')));
      expect(pubspec, isNot(contains('.otf\n          weight')));
    });
  });
}
