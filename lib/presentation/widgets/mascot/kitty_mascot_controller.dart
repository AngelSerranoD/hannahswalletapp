import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/mascot_state.dart';

/// Los tres clips del gato.
enum KittyClip {
  /// Bucle permanente: respira, parpadea, mueve la cola.
  idle,

  /// Salto con monedas. Se reproduce una vez y vuelve a [idle].
  celebrate,

  /// Temblor y gota de sudor. Una vez, o en bucle si el presupuesto sigue
  /// por encima del 90 %.
  alert,
}

/// Maquina de estados de la mascota.
///
/// Es el equivalente a la `StateMachine` que expondria un fichero Rive, pero
/// escrita en Dart porque las animaciones son Lottie. La API imita a proposito
/// la de Rive para que el resto de la app hable el mismo lenguaje:
///
///   * [budgetHealth]   <- el `SMIInput<double>` (0 = agotado, 1 = intacto)
///   * [fireSuccess]    <- el `SMITrigger successTrigger`
///   * [fireAlert]      <- el `SMITrigger alertTrigger`
///
/// La diferencia práctica es que aquí las transiciones son explicitas y se
/// pueden leer: un `budgetHealth` por debajo del umbral no solo cambia un
/// número, decide si al terminar un clip se vuelve a reposo o se insiste en la
/// alerta.
class KittyMascotController extends ChangeNotifier {
  KittyMascotController({double budgetHealth = 1})
      : _budgetHealth = budgetHealth.clamp(0.0, 1.0);

  double _budgetHealth;
  KittyClip _clip = KittyClip.idle;

  /// Se incrementa en cada disparo. El widget lo usa para distinguir "el mismo
  /// clip otra vez" de "sigue el mismo clip": sin este contador, pulsar dos
  /// veces seguidas guardar un gasto no relanzaria la celebracion, porque el
  /// valor de [clip] no habria cambiado y `didUpdateWidget` no veria nada.
  int _pulse = 0;

  /// Salud del presupuesto: 1 = intacto, 0 = agotado.
  double get budgetHealth => _budgetHealth;

  KittyClip get clip => _clip;

  int get pulse => _pulse;

  /// `true` cuando la alerta debe mantenerse en bucle en lugar de volver a
  /// reposo: por encima del 90 % consumido el gato no se relaja.
  bool get isDistressed =>
      _budgetHealth <= (1 - AppConstants.budgetAlertThreshold);

  /// Actualiza la salud. Equivale a escribir en el input numerico de Rive.
  ///
  /// Además de guardar el valor, decide sola si hay que reaccionar: al CRUZAR
  /// el umbral del 90 % dispara la alerta una vez. Se comprueba el cruce y no
  /// el valor absoluto para no relanzar la animación en cada refresco mientras
  /// el usuario siga por encima del límite; sería insufrible.
  set budgetHealth(double value) {
    final double next = value.clamp(0.0, 1.0);
    if ((next - _budgetHealth).abs() < 0.001) return;

    const double threshold = 1 - AppConstants.budgetAlertThreshold;
    final bool wasSafe = _budgetHealth > threshold;
    final bool isNowCritical = next <= threshold;

    _budgetHealth = next;

    if (wasSafe && isNowCritical) {
      fireAlert();
      return;
    }

    // Si estaba en alerta en bucle y el usuario ha recuperado margen (por
    // ejemplo borrando un gasto o subiendo el límite), se vuelve a reposo.
    if (_clip == KittyClip.alert && !isDistressed) {
      _setClip(KittyClip.idle);
      return;
    }

    notifyListeners();
  }

  /// Aplica el estado calculado desde el presupuesto real.
  void applyState(MascotState state) {
    budgetHealth = state.budgetHealth;
  }

  /// Celebracion. La invoca la UI tras guardar un movimiento con exito.
  void fireSuccess() => _setClip(KittyClip.celebrate, force: true);

  /// Alerta. La invoca la UI, o el propio setter de [budgetHealth] al cruzar
  /// el 90 %.
  void fireAlert() => _setClip(KittyClip.alert, force: true);

  /// Vuelve a reposo. Lo llama el widget cuando termina un clip de una sola
  /// pasada, salvo que la situacion siga siendo critica.
  void returnToIdle() {
    if (isDistressed) {
      if (_clip != KittyClip.alert) _setClip(KittyClip.alert);
      return;
    }
    if (_clip != KittyClip.idle) _setClip(KittyClip.idle);
  }

  void _setClip(KittyClip next, {bool force = false}) {
    if (!force && _clip == next) return;
    _clip = next;
    _pulse++;
    notifyListeners();
  }
}
