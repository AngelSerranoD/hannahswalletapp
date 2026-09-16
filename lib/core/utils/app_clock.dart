import 'package:flutter/foundation.dart';

/// La hora de la app. En producción es `DateTime.now()`.
///
/// Existe para que las pruebas puedan fijar el día. Las capturas de pantalla
/// (goldens) enseñan el mes en curso, "Hoy", "Ayer" o el día de la semana, y
/// con el reloj real caducaban solas: una captura generada en agosto fallaba
/// en septiembre sin que nadie hubiese tocado nada. Un test que falla por el
/// calendario deja de vigilar, porque se acaba ignorando.
abstract final class AppClock {
  static DateTime Function() _now = DateTime.now;

  static DateTime now() => _now();

  /// Congela el reloj en [moment]. Solo para pruebas.
  @visibleForTesting
  static void fix(DateTime moment) => _now = () => moment;

  /// Vuelve al reloj real.
  @visibleForTesting
  static void reset() => _now = DateTime.now;
}
