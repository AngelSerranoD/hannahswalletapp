import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';

/// Humor del gato. Es la traduccion de un número frio (el porcentaje de
/// presupuesto consumido) a algo que se entiende de un vistazo.
enum MascotMood {
  /// Queda mucho margen. El gato esta relajado.
  relaxed('Vas holgado'),

  /// Consumo normal para lo que va de mes.
  content('Todo en orden'),

  /// Empieza a apretar: por encima del 70 %.
  watchful('Ojo con el ritmo'),

  /// Al límite: por encima del 90 %. Es el umbral que pediste vigilar.
  alarmed('Casi sin margen'),

  /// Presupuesto rebasado.
  overspent('Te has pasado');

  const MascotMood(this.headline);

  final String headline;
}

/// Estado completo que consume `KittyMascotWidget`.
///
/// [budgetHealth] va de 0 (presupuesto agotado) a 1 (intacto). Se expone como
/// `double` continuo, y no solo como [MascotMood], para que la animación pueda
/// interpolar de forma fluida en vez de saltar entre cuatro poses fijas.
class MascotState extends Equatable {
  const MascotState({
    required this.budgetHealth,
    required this.mood,
    required this.consumedRatio,
    this.hasBudget = true,
  });

  /// Estado neutro mientras no hay datos o no hay ningún presupuesto definido.
  factory MascotState.neutral() => const MascotState(
        budgetHealth: 1,
        mood: MascotMood.content,
        consumedRatio: 0,
        hasBudget: false,
      );

  /// Deriva el estado del porcentaje consumido del presupuesto del mes.
  ///
  /// Los cortes salen de [AppConstants]: 70 % vigilancia, 90 % alarma. El 90 %
  /// es el punto en el que la mascota cambia de verdad de cara y dispara la
  /// animación de alerta.
  factory MascotState.fromRatio(double ratio, {bool hasBudget = true}) {
    final double safeRatio = ratio.isFinite && ratio > 0 ? ratio : 0;
    final double health = (1 - safeRatio).clamp(0.0, 1.0);

    final MascotMood mood;
    if (safeRatio > 1.0) {
      mood = MascotMood.overspent;
    } else if (safeRatio >= AppConstants.budgetAlertThreshold) {
      mood = MascotMood.alarmed;
    } else if (safeRatio >= AppConstants.budgetWarningThreshold) {
      mood = MascotMood.watchful;
    } else if (safeRatio >= 0.35) {
      mood = MascotMood.content;
    } else {
      mood = MascotMood.relaxed;
    }

    return MascotState(
      budgetHealth: health,
      mood: mood,
      consumedRatio: safeRatio,
      hasBudget: hasBudget,
    );
  }

  /// 1 = presupuesto intacto, 0 = agotado.
  final double budgetHealth;
  final MascotMood mood;

  /// Fraccion consumida sin recortar (puede superar 1).
  final double consumedRatio;

  /// `false` si el usuario aun no ha definido ningún presupuesto: el gato no
  /// debe alarmarse por algo que nadie ha configurado.
  final bool hasBudget;

  bool get shouldAlert =>
      hasBudget && consumedRatio >= AppConstants.budgetAlertThreshold;

  @override
  List<Object?> get props =>
      <Object?>[budgetHealth, mood, consumedRatio, hasBudget];
}
