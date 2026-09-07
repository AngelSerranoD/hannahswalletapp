import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/domain/entities/mascot_state.dart';
import 'package:hannahswalletapp/presentation/widgets/mascot/kitty_mascot_controller.dart';

/// Pruebas del enlace presupuesto -> mascota.
///
/// Es la pieza que pedia el Modulo 4: que el gato reaccione al 90 % del
/// presupuesto consumido, y que lo haga UNA vez y no en cada refresco.
void main() {
  group('MascotState.fromRatio', () {
    test('budgetHealth es el complemento de lo consumido', () {
      expect(MascotState.fromRatio(0).budgetHealth, 1.0);
      expect(MascotState.fromRatio(0.25).budgetHealth, closeTo(0.75, 1e-9));
      expect(MascotState.fromRatio(1).budgetHealth, 0.0);
    });

    test('nunca se sale de [0, 1] aunque se dispare el gasto', () {
      expect(MascotState.fromRatio(3.5).budgetHealth, 0.0);
      expect(MascotState.fromRatio(-1).budgetHealth, 1.0);
    });

    test('asigna el humor por tramos', () {
      expect(MascotState.fromRatio(0.10).mood, MascotMood.relaxed);
      expect(MascotState.fromRatio(0.50).mood, MascotMood.content);
      expect(MascotState.fromRatio(0.75).mood, MascotMood.watchful);
      expect(MascotState.fromRatio(0.95).mood, MascotMood.alarmed);
      expect(MascotState.fromRatio(1.30).mood, MascotMood.overspent);
    });

    test('el 90 % exacto ya es alarma', () {
      expect(MascotState.fromRatio(0.90).mood, MascotMood.alarmed);
      expect(MascotState.fromRatio(0.90).shouldAlert, isTrue);
      expect(MascotState.fromRatio(0.89).shouldAlert, isFalse);
    });

    test('sin presupuesto definido el gato no se alarma', () {
      final MascotState neutral = MascotState.neutral();
      expect(neutral.hasBudget, isFalse);
      expect(neutral.shouldAlert, isFalse);
    });
  });

  group('KittyMascotController', () {
    test('parte en reposo con salud plena', () {
      final KittyMascotController c = KittyMascotController();
      expect(c.clip, KittyClip.idle);
      expect(c.budgetHealth, 1.0);
      c.dispose();
    });

    test('dispara la alerta al CRUZAR el umbral del 90 %', () {
      final KittyMascotController c = KittyMascotController();
      c.budgetHealth = 0.5; // 50 % consumido
      expect(c.clip, KittyClip.idle);

      c.budgetHealth = 0.05; // 95 % consumido
      expect(c.clip, KittyClip.alert);
      c.dispose();
    });

    test('no relanza la alerta mientras sigue por encima del umbral', () {
      final KittyMascotController c = KittyMascotController();
      c.budgetHealth = 0.05;
      final int pulseTrasAlerta = c.pulse;

      // Otro gasto que empeora un poco mas la situacion: el gato ya esta
      // alarmado, y volver a lanzar la animacion en cada refresco seria
      // insufrible.
      c.budgetHealth = 0.02;
      expect(c.pulse, pulseTrasAlerta);
      c.dispose();
    });

    test('vuelve a reposo si se recupera margen', () {
      final KittyMascotController c = KittyMascotController();
      c.budgetHealth = 0.05;
      expect(c.clip, KittyClip.alert);

      // El usuario borra un gasto o sube el limite.
      c.budgetHealth = 0.6;
      expect(c.clip, KittyClip.idle);
      c.dispose();
    });

    test('la celebracion se puede repetir seguida', () {
      final KittyMascotController c = KittyMascotController();
      c.fireSuccess();
      final int primera = c.pulse;
      c.fireSuccess();
      // El contador de pulsos es lo que permite al widget distinguir dos
      // celebraciones consecutivas de "no ha cambiado nada".
      expect(c.pulse, greaterThan(primera));
      c.dispose();
    });

    test('returnToIdle mantiene la alerta si sigue en apuros', () {
      final KittyMascotController c = KittyMascotController();
      c.budgetHealth = 0.02;
      c.fireSuccess();
      expect(c.clip, KittyClip.celebrate);

      c.returnToIdle();
      expect(c.clip, KittyClip.alert);
      c.dispose();
    });

    test('applyState traduce el estado de dominio', () {
      final KittyMascotController c = KittyMascotController();
      c.applyState(MascotState.fromRatio(0.95));
      expect(c.isDistressed, isTrue);
      expect(c.clip, KittyClip.alert);
      c.dispose();
    });
  });
}
