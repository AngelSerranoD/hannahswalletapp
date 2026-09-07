import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auto_lock_provider.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/mascot_state.dart';
import 'kitty_animations.dart';
import 'kitty_mascot_controller.dart';

/// Composiciones Lottie parseadas una sola vez por proceso.
///
/// `LottieComposition.parseJsonBytes` es SINCRONO, así que no hace falta ni
/// `FutureBuilder` ni un estado de carga: el gato esta en el primer frame. Pero
/// procesar 70 KB de JSON tres veces cuesta unos milisegundos, y el dashboard
/// se reconstruye a menudo, de modo que el resultado se guarda aquí.
abstract final class KittyCompositions {
  static LottieComposition? _idle;
  static LottieComposition? _celebrate;
  static LottieComposition? _alert;
  static bool _failed = false;

  static LottieComposition? of(KittyClip clip) {
    if (_failed) return null;
    try {
      switch (clip) {
        case KittyClip.idle:
          return _idle ??= _parse(kittyIdleAnimation);
        case KittyClip.celebrate:
          return _celebrate ??= _parse(kittyCelebrateAnimation);
        case KittyClip.alert:
          return _alert ??= _parse(kittyAlertAnimation);
      }
    } catch (error, stack) {
      // Si el JSON generado tuviese un fallo, la app NO debe caerse por una
      // mascota decorativa: se marca el fallo y se pinta el gato estatico.
      debugPrint('Kitty: no se pudo parsear la animación ($error)\n$stack');
      _failed = true;
      return null;
    }
  }

  static LottieComposition _parse(String json) =>
      LottieComposition.parseJsonBytes(utf8.encode(json));

  /// Fuerza el parseo de los tres clips. Se llama al arrancar para que el
  /// primer salto de celebracion no tenga que parsear nada a mitad de gesto.
  static void warmUp() {
    for (final KittyClip clip in KittyClip.values) {
      of(clip);
    }
  }
}

/// La mascota interactiva que corona el dashboard.
///
/// Encapsula toda la lógica de animación: el resto de la app solo habla con
/// [KittyMascotController] ([KittyMascotController.budgetHealth],
/// [KittyMascotController.fireSuccess], [KittyMascotController.fireAlert]) y
/// nunca toca Lottie directamente.
class KittyMascotWidget extends ConsumerStatefulWidget {
  const KittyMascotWidget({
    required this.controller,
    this.state,
    this.size = 132,
    this.onTap,
    super.key,
  });

  final KittyMascotController controller;

  /// Estado de presupuesto, solo para la etiqueta accesible y el aro de color.
  final MascotState? state;

  final double size;

  /// Un toque en el gato también dispara la celebracion: la mascota tiene que
  /// responder al usuario, no solo a los datos.
  final VoidCallback? onTap;

  @override
  ConsumerState<KittyMascotWidget> createState() => _KittyMascotWidgetState();
}

class _KittyMascotWidgetState extends ConsumerState<KittyMascotWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  KittyClip _clip = KittyClip.idle;
  int _lastPulse = -1;

  /// Corta el bucle de reposo cuando el usuario lleva un rato sin tocar nada.
  ///
  /// Este temporizador es la diferencia entre una app fresca y un movil que
  /// arde en el bolsillo. La animacion de reposo se repetia SIEMPRE: sesenta
  /// repintados por segundo, indefinidamente, aunque el telefono estuviera
  /// encima de la mesa. Ahora el gato respira mientras se le hace caso y se
  /// queda quieto -en su fotograma, sin desaparecer- cuando no.
  Timer? _idleStop;

  /// Cuanto sigue animando tras la ultima interaccion.
  static const Duration _idleGrace = Duration(seconds: 12);

  ValueNotifier<int>? _activity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)..addStatusListener(_onStatus);
    widget.controller.addListener(_onControllerChanged);
    _clip = widget.controller.clip;
    _lastPulse = widget.controller.pulse;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activity = ref.read(autoLockProvider).activity..addListener(_onActivity);
      _play(_clip);
    });
  }

  /// El usuario ha hecho algo: el gato vuelve a moverse y se reinicia la
  /// cuenta atras.
  void _onActivity() {
    if (!mounted) return;
    if (_clip == KittyClip.idle && !_anim.isAnimating) _play(KittyClip.idle);
    _armIdleStop();
  }

  void _armIdleStop() {
    _idleStop?.cancel();
    _idleStop = Timer(_idleGrace, () {
      // Solo se detiene el reposo: una celebracion o una alerta en curso
      // terminan siempre, porque son la respuesta a algo que acaba de pasar.
      if (mounted && _clip == KittyClip.idle) _anim.stop();
    });
  }

  @override
  void didUpdateWidget(covariant KittyMascotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    _idleStop?.cancel();
    _activity?.removeListener(_onActivity);
    widget.controller.removeListener(_onControllerChanged);
    _anim.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final KittyMascotController c = widget.controller;

    // El pulso distingue "vuelve a disparar el mismo clip" de "nada nuevo".
    final bool retrigger = c.pulse != _lastPulse;
    if (c.clip != _clip || retrigger) {
      _lastPulse = c.pulse;
      setState(() => _clip = c.clip);
      _play(c.clip);
      return;
    }

    // Solo cambio la salud: basta con ajustar el ritmo del reposo.
    if (_clip == KittyClip.idle) {
      _anim.duration = _idleDuration();
    }
    if (mounted) setState(() {});
  }

  /// El reposo se ralentiza cuanto peor va el presupuesto.
  ///
  /// Es el uso continuo de `budgetHealth`: sin necesidad de leer un número, un
  /// gato que respira despacio ya comunica que la cosa esta apretada.
  Duration _idleDuration() {
    final LottieComposition? comp = KittyCompositions.of(KittyClip.idle);
    final Duration base = comp?.duration ?? const Duration(seconds: 3);
    final double health = widget.controller.budgetHealth;
    final double factor = 1.0 + (1.0 - health) * 0.6; // hasta un 60 % mas lento
    return base * factor;
  }

  void _play(KittyClip clip) {
    final LottieComposition? comp = KittyCompositions.of(clip);
    if (comp == null || !mounted) return;

    _anim.stop();
    switch (clip) {
      case KittyClip.idle:
        _anim.duration = _idleDuration();
        _anim.repeat();
        _armIdleStop();
      case KittyClip.celebrate:
        _anim.duration = comp.duration;
        _anim.forward(from: 0);
      case KittyClip.alert:
        _anim.duration = comp.duration;
        // En apuros la alerta se queda en bucle; si fue un aviso puntual,
        // `_onStatus` la devolvera a reposo al terminar.
        if (widget.controller.isDistressed) {
          _anim.repeat();
        } else {
          _anim.forward(from: 0);
        }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_clip == KittyClip.idle) return;
    widget.controller.returnToIdle();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MascotState state = widget.state ?? MascotState.neutral();
    final LottieComposition? composition = KittyCompositions.of(_clip);

    return Semantics(
      label: 'Mascota: ${state.mood.headline}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: () {
          widget.controller.fireSuccess();
          widget.onTap?.call();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              RepaintBoundary(child: _MoodHalo(state: state, size: widget.size)),
              if (composition != null)
                Lottie(
                  composition: composition,
                  controller: _anim,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.contain,
                  // El gato es decorativo y se repinta 60 veces por segundo:
                  // aislarlo en su propia capa evita que arrastre consigo el
                  // repintado del saldo y de la lista de movimientos.
                  addRepaintBoundary: true,
                  // `none`: el dibujo es vectorial y se pinta al tamano al que
                  // se compuso, asi que el filtrado bilineal solo anadiria
                  // trabajo por fotograma sin cambiar nada en pantalla.
                  filterQuality: FilterQuality.none,
                )
              else
                _StaticKittyFallback(size: widget.size, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aro de color detras del gato: verde holgado, ambar ajustado, rojo al límite.
///
/// Duplica en color lo que la animación dice con gestos. Es deliberado: el
/// estado del presupuesto no debe depender solo de saber leer la cara de un
/// gato, ni solo del color, que no todo el mundo distingue igual.
class _MoodHalo extends StatelessWidget {
  const _MoodHalo({required this.state, required this.size});

  final MascotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Sin color, el humor se transmite por INTENSIDAD: cuanto peor va el
    // presupuesto, más oscuro y más presente es el halo. Con los cinco estados
    // asignados a colores semánticos, en monocromo tres de ellos caían en la
    // misma tinta y el halo dejaba de decir nada.
    //
    // El halo nunca va solo: al lado se lee "Todo en orden" o "Casi sin
    // margen", que es lo que de verdad informa. Esto lo refuerza.
    final (Color color, double strength) = switch (state.mood) {
      MascotMood.relaxed => (AppColors.moss, 0.50),
      MascotMood.content => (AppColors.secondary, 0.55),
      MascotMood.watchful => (AppColors.warning, 0.70),
      MascotMood.alarmed => (AppColors.rosyBrown, 0.85),
      MascotMood.overspent => (AppColors.danger, 0.95),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      width: size * 0.92,
      height: size * 0.92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color.withValues(alpha: state.hasBudget ? strength * 0.42 : 0.12),
            color.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.35, 1.0],
        ),
      ),
    );
  }
}

/// Gato estatico de emergencia si el Lottie no cargase.
class _StaticKittyFallback extends StatelessWidget {
  const _StaticKittyFallback({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.pets_rounded, size: size * 0.5, color: color);
  }
}
