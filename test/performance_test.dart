import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/utils/date_range.dart';
import 'package:hannahswalletapp/core/utils/money.dart';
import 'package:hannahswalletapp/domain/entities/mascot_state.dart';
import 'package:hannahswalletapp/presentation/providers/auto_lock_provider.dart';
import 'package:hannahswalletapp/presentation/widgets/mascot/kitty_mascot_controller.dart';
import 'package:hannahswalletapp/presentation/widgets/mascot/kitty_mascot_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pruebas de consumo.
///
/// El móvil se calentaba con la app abierta. La causa era la mascota: su
/// animación de reposo se repetía indefinidamente, sesenta repintados por
/// segundo, aunque el teléfono estuviera encima de la mesa o el usuario
/// estuviera en otra pestaña.
///
/// `transientCallbackCount` es el número de animaciones vivas en el árbol, así
/// que sirve de medida directa: **cero significa que nada está pidiendo
/// fotogramas**. Estas pruebas existen porque la regresión sería invisible —la
/// app se vería exactamente igual— y solo se notaría en la batería.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));

  Widget host(KittyMascotController controller) {
    return ProviderScope(
      child: MaterialApp(
        home: ActivityDetector(
          child: Scaffold(
            body: Center(
              child: KittyMascotWidget(
                controller: controller,
                state: MascotState.neutral(),
                size: 120,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('la mascota no anima para siempre', () {
    testWidgets('se detiene tras el margen de inactividad',
        (WidgetTester tester) async {
      final KittyMascotController controller = KittyMascotController();
      await tester.pumpWidget(host(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Arranca animando: el gato respira cuando llegas.
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'Al abrir, la mascota debe estar animando');

      // Sin tocar nada, pasa el margen de gracia.
      await tester.pump(const Duration(seconds: 13));
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0,
          reason: 'Sin interacción, la animación debe pararse: es lo que '
              'evita que el móvil se caliente con la app abierta');
    });

    testWidgets('vuelve a animar al tocar la pantalla',
        (WidgetTester tester) async {
      final KittyMascotController controller = KittyMascotController();
      await tester.pumpWidget(host(controller));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pump(const Duration(seconds: 13));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      // Un toque en cualquier parte la revive.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'Al volver a usar la app, el gato debe volver a moverse');
    });

    testWidgets('TickerMode la congela cuando no se ve',
        (WidgetTester tester) async {
      final KittyMascotController controller = KittyMascotController();
      bool visible = true;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Scaffold(
                  body: Column(
                    children: <Widget>[
                      TickerMode(
                        enabled: visible,
                        child: KittyMascotWidget(
                          controller: controller,
                          state: MascotState.neutral(),
                          size: 120,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => visible = false),
                        child: const Text('ocultar'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // Cambiar de pestaña equivale a esto: el widget sigue montado pero sus
      // tickers se desconectan. Sin ello, la mascota seguía repintándose
      // mientras el usuario miraba Ajustes.
      await tester.tap(find.text('ocultar'));
      await tester.pump();
      // Margen para que termine la transicion del halo, que es la unica otra
      // animacion del arbol.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.binding.transientCallbackCount, 0,
          reason: 'Fuera de la pestaña visible no debe consumir nada');
    });
  });

  group('formateadores reutilizados', () {
    test('el mismo formato devuelve la misma instancia', () {
      // `NumberFormat` y `DateFormat` compilan su patrón al construirse, y la
      // lista de movimientos los pedía una vez por fila y por fotograma.
      final DateFormatLike a = DateFormatLike(AppDates.fmt('d MMM y'));
      final DateFormatLike b = DateFormatLike(AppDates.fmt('d MMM y'));
      expect(identical(a.inner, b.inner), isTrue,
          reason: 'Debe reutilizarse el formateador ya construido');
    });

    test('formatear muchos importes no degrada el resultado', () {
      // Comprobación de que la caché no rompe nada: mismos valores de siempre.
      // El simbolo va separado por un espacio DURO (U+00A0), que es lo que
      // pone `intl`: escribirlo aqui con un espacio normal haria fallar la
      // comparacion por un caracter invisible.
      const String nbsp = ' ';
      const String esperado = '1.776,70$nbsp€';

      expect(Money.format(177670), esperado);
      expect(Money.format(0), '0,00$nbsp€');
      for (int i = 0; i < 500; i++) {
        Money.format(i * 137);
      }
      expect(Money.format(177670), esperado,
          reason: 'La cache no puede alterar el resultado');
    });
  });
}

/// Envoltorio mínimo para comparar identidad de formateadores sin exponer
/// detalles internos de `intl`.
class DateFormatLike {
  const DateFormatLike(this.inner);
  final Object inner;
}
