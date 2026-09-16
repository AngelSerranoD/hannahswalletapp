import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/app.dart';
import 'package:hannahswalletapp/core/di/providers.dart';
import 'package:hannahswalletapp/data/backend/web/vault_store.dart';
import 'package:hannahswalletapp/data/backend/web_backend.dart';
import 'package:hannahswalletapp/presentation/screens/settings/settings_screen.dart';
import 'package:idb_shim/idb_client_memory.dart';

/// Recorrido completo de usuario sobre la app REAL.
///
/// No prueba una pantalla suelta: arranca `HannahsWalletApp` entera, con su
/// arranque, sus puertas de seguridad y su backend cifrado, y hace lo que haría
/// una persona: crear la bóveda, anotar un gasto, comprobar el saldo, bloquear
/// y volver a entrar.
///
/// Es la prueba que detecta lo que se les escapa a las unitarias: que dos
/// piezas correctas por separado no encajen entre ellas.
void main() {
  const String pass = 'contrasena-de-prueba';

  setUp(() async => VaultStore(factory: idbFactoryMemory).delete());

  /// Avanza la interfaz dejando correr también la E/S real.
  ///
  /// `pumpAndSettle` no sirve en esta app: la mascota tiene una animación en
  /// bucle que nunca termina y esperaría para siempre. Y `pump` a secas no
  /// basta, porque el reloj de `flutter_test` es falso y no avanza los
  /// temporizadores de IndexedDB ni del guardado diferido; de ahí el
  /// `runAsync` intercalado.
  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 80));
  }

  Future<void> launch(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBackendProvider.overrideWithValue(
            WebBackend(
              store: VaultStore(factory: idbFactoryMemory),
              // Coste bajo: la prueba mide que el flujo encaje, no la fuerza
              // del KDF, que ya se comprueba en `security_test.dart`.
              kdfIterations: 1000,
            ),
          ),
        ],
        child: const HannahsWalletApp(),
      ),
    );
    await settle(tester, rounds: 14);
  }

  testWidgets('crear la bóveda, anotar un gasto y volver a entrar',
      (WidgetTester tester) async {
    await launch(tester);

    // ---------------------------------------------- 1. Puerta de la bóveda
    expect(find.text('Protege tus cuentas'), findsOneWidget,
        reason: 'La app debe arrancar pidiendo crear la bóveda');

    final Finder passField = find.byType(TextField).first;
    final Finder confirmField = find.byType(TextField).at(1);

    // Contraseña demasiado corta.
    await tester.enterText(passField, 'corta');
    await tester.enterText(confirmField, 'corta');
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester);
    expect(find.textContaining('al menos'), findsOneWidget,
        reason: 'Debe rechazar una contraseña corta');

    // Longitud correcta pero sin aceptar el aviso.
    await tester.enterText(passField, pass);
    await tester.enterText(confirmField, pass);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester);
    expect(find.textContaining('no se puede recuperar'), findsWidgets,
        reason: 'No debe crear la bóveda sin confirmar que se entiende el '
            'riesgo de olvidar la contraseña');

    // Ahora sí.
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);

    // ------------------------------------------------------ 2. Dashboard
    expect(find.text('Saldo acumulado'), findsOneWidget,
        reason: 'Tras crear la bóveda debe entrar al dashboard');
    expect(find.text('Movimientos recientes'), findsOneWidget);
    expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);

    // ------------------------------------------------- 3. Anotar un gasto
    await tester.tap(find.text('Nuevo gasto'));
    await settle(tester, rounds: 8);
    expect(find.text('Nuevo movimiento'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '42,90');
    await settle(tester, rounds: 4);

    // Elegir categoría de la rejilla.
    await tester.tap(find.text('Alimentación').first);
    await settle(tester, rounds: 4);

    await tester.tap(find.text('Guardar'));
    await settle(tester, rounds: 16);

    // ------------------------------------- 4. El gasto llega al dashboard
    expect(find.text('Saldo acumulado'), findsOneWidget,
        reason: 'Al guardar debe volver al dashboard');
    expect(find.textContaining('42,90'), findsWidgets,
        reason: 'El gasto recién anotado debe aparecer');
    expect(find.text('Alimentación'), findsWidgets);

    // ----------------------------------------------- 5. Bloquear la bóveda
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester, rounds: 8);

    await tester.dragUntilVisible(
      find.text('Bloquear ahora'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await settle(tester, rounds: 4);

    await tester.tap(find.text('Bloquear ahora'));
    await settle(tester, rounds: 12);

    expect(find.text('Desbloquear'), findsOneWidget,
        reason: 'Bloquear debe devolver a la puerta de la bóveda');
    expect(find.text('Saldo acumulado'), findsNothing,
        reason: 'Con la bóveda cerrada no puede verse ningún dato');

    // -------------------------------------- 6. Contraseña incorrecta y OK
    await tester.enterText(find.byType(TextField).first, 'no-es-la-buena');
    await tester.tap(find.text('Desbloquear'));
    await settle(tester, rounds: 14);
    expect(find.text('Contraseña incorrecta.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, pass);
    await tester.tap(find.text('Desbloquear'));
    await settle(tester, rounds: 18);

    // ------------------------------------------- 7. Los datos siguen ahí
    expect(find.text('Saldo acumulado'), findsOneWidget);
    expect(find.textContaining('42,90'), findsWidgets,
        reason: 'El gasto debe haber sobrevivido al ciclo de cifrado, '
            'bloqueo y descifrado');
  });

  testWidgets('un presupuesto cambia el ánimo de la mascota',
      (WidgetTester tester) async {
    await launch(tester);

    // Crear bóveda.
    await tester.enterText(find.byType(TextField).first, pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);

    // Sin presupuesto, el gato no se alarma.
    expect(find.text('Todo en orden'), findsOneWidget);

    // Crear un límite de 50 EUR.
    await tester.tap(find.byIcon(Icons.savings_outlined).first);
    await settle(tester, rounds: 8);
    await tester.tap(find.text('Nuevo límite'));
    await settle(tester, rounds: 8);

    await tester.enterText(
        find.widgetWithText(TextField, 'Límite mensual'), '50');
    await settle(tester, rounds: 4);

    // El panel se desplaza: sin esto el toque caería fuera de la pantalla y
    // el boton no llegaria a pulsarse.
    await tester.ensureVisible(find.text('Guardar'));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Guardar'));
    await settle(tester, rounds: 12);

    expect(find.textContaining('50,00'), findsWidgets,
        reason: 'El presupuesto debe aparecer en la lista');

    // Anotar un gasto que consuma el 90 % del presupuesto.
    await tester.tap(find.byIcon(Icons.home_outlined).first);
    await settle(tester, rounds: 8);

    await tester.tap(find.text('Nuevo gasto'));
    await settle(tester, rounds: 8);
    await tester.enterText(find.byType(TextField).first, '46');
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Guardar'));
    await settle(tester, rounds: 16);

    // 46 de 50 son el 92 %: por encima del umbral de alarma.
    expect(find.text('Casi sin margen'), findsOneWidget,
        reason: 'Al pasar del 90 % del presupuesto la mascota debe alarmarse');
    expect(find.textContaining('92 %'), findsWidgets);
  });

  testWidgets('un límite con nombre agrupa categorías y descuenta del total',
      (WidgetTester tester) async {
    await launch(tester);

    await tester.enterText(find.byType(TextField).first, pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);

    await tester.tap(find.byIcon(Icons.savings_outlined).first);
    await settle(tester, rounds: 8);

    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await settle(tester, rounds: 2);
      await tester.tap(finder);
      await settle(tester, rounds: 8);
    }

    // Total del mes: 500 EUR.
    await tester.tap(find.text('Nuevo límite'));
    await settle(tester, rounds: 8);
    await tester.enterText(
        find.widgetWithText(TextField, 'Límite mensual'), '500');
    await tapVisible(find.text('Guardar'));

    // "Finde": 120 EUR entre Restaurantes, Ocio y una categoría creada aquí.
    await tester.tap(find.text('Nuevo límite'));
    await settle(tester, rounds: 8);
    await tester.tap(find.text('Categorías'));
    await settle(tester, rounds: 4);
    await tester.enterText(
        find.widgetWithText(TextField, 'Límite mensual'), '120');
    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre (opcional)'), 'Finde');
    await settle(tester, rounds: 4);
    await tapVisible(find.text('Restaurantes'));
    await tapVisible(find.text('Ocio'));

    await tapVisible(find.text('Nueva categoría'));
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Conciertos');
    await settle(tester, rounds: 4);
    // Hay dos "Guardar": el de la categoría es el de la hoja de encima.
    await tapVisible(find.text('Guardar').last);
    expect(find.text('Conciertos'), findsOneWidget,
        reason: 'La categoría nueva entra ya marcada en el límite');

    await tapVisible(find.text('Guardar'));

    expect(find.text('Finde'), findsOneWidget);
    expect(find.textContaining('Restaurantes, Ocio y Conciertos'), findsOneWidget);
    expect(find.textContaining('380,00'), findsWidgets,
        reason: 'El total de 500 menos los 120 del límite');

    // Otra vez: Ocio ya está en "Finde" y no se puede meter en otro límite.
    await tester.tap(find.text('Nuevo límite'));
    await settle(tester, rounds: 8);
    await tester.tap(find.text('Categorías'));
    await settle(tester, rounds: 4);
    expect(find.text('Ocio · en Finde'), findsOneWidget);
  });

  testWidgets('una regla recurrente se guarda con la cartera predeterminada',
      (WidgetTester tester) async {
    await launch(tester);

    await tester.enterText(find.byType(TextField).first, pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tester.tap(find.text('Lo entiendo'));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Crear bóveda'));
    await settle(tester, rounds: 16);

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await settle(tester, rounds: 8);
    // La lista de Ajustes es perezosa: la fila no existe hasta desplazarse.
    await tester.scrollUntilVisible(
      find.text('Movimientos recurrentes'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Movimientos recurrentes'));
    await settle(tester, rounds: 8);

    await tester.tap(find.text('Nueva regla'));
    await settle(tester, rounds: 8);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '30');
    await tester.enterText(find.widgetWithText(TextField, 'Concepto'), 'Gimnasio');
    await settle(tester, rounds: 4);

    // No se toca la cartera: la hoja tiene que usar la predeterminada. Si no
    // la resolviese al guardar, la regla se quedaría sin cartera y no saldría.
    await tester.ensureVisible(find.text('Guardar'));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Guardar'));
    await settle(tester, rounds: 12);

    expect(find.text('Guardar'), findsNothing, reason: 'La hoja se cierra');
    expect(find.textContaining('Gimnasio'), findsWidgets);
  });
}
