import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/backend/app_backend.dart';
import 'app_settings_provider.dart';

/// Cierra la bóveda sola cuando la app queda desatendida.
///
/// **Por qué hace falta**: el cifrado protege los datos EN REPOSO. Una vez
/// abierta la bóveda, la clave está en memoria y todo es legible; si el
/// dispositivo se queda encima de una mesa con la app abierta, el cifrado no
/// sirve de nada. Cerrar la sesión descarta la clave y devuelve los datos a
/// ese estado protegido.
///
/// Dos disparadores:
///
///  * **Inactividad**: cualquier toque o desplazamiento reinicia la cuenta.
///    El plazo lo elige el usuario en Ajustes (0 = nunca).
///  * **Segundo plano**: al salir de la app se bloquea de inmediato, sin
///    margen. En iOS el sistema puede descargar la pestaña sin avisar, y
///    volver a pedir Face ID cuesta un segundo; dejar la sesión viva "por
///    comodidad" es justo lo que aprovecharía quien coja el móvil.
class AutoLockController {
  AutoLockController(this._ref);

  final Ref _ref;
  Timer? _idleTimer;

  /// Ventana abierta del limitador. Mientras corra, los avisos se ignoran.
  ///
  /// Se usa un [Timer] y no `DateTime.now()` a propósito: los temporizadores
  /// los controla el reloj de las pruebas, así que el limitador se puede
  /// comprobar. Con la hora del sistema, un test que avanza el reloj falso no
  /// afecta al real y el comportamiento quedaba sin cubrir.
  Timer? _throttleWindow;

  /// Pulso de actividad del usuario.
  ///
  /// Lo escucha la mascota para saber si merece la pena seguir animando: un
  /// gato respirando a sesenta fotogramas por segundo delante de un móvil que
  /// nadie está mirando es puro calor y batería.
  final ValueNotifier<int> activity = ValueNotifier<int>(0);

  /// Cada cuánto se atiende un aviso de actividad como mucho.
  ///
  /// Un desplazamiento con el dedo genera cientos de eventos por segundo, y
  /// cada uno cancelaba y recreaba el temporizador de bloqueo. Con un segundo
  /// de margen el comportamiento es idéntico y el trabajo baja tres órdenes de
  /// magnitud.
  static const Duration _throttle = Duration(seconds: 1);

  Duration get _idleDelay {
    final int minutes = _ref.read(settingsSnapshotProvider).autoLockMinutes;
    return Duration(minutes: minutes);
  }

  bool get _isRelevant {
    // Solo tiene sentido donde cerrar la sesión signifique algo: en móvil la
    // clave la devuelve el sistema al instante, así que el bloqueo de pantalla
    // (biometría o PIN) es la capa que corresponde, y de esa se encarga
    // `AppLockNotifier`.
    if (!_ref.read(appBackendProvider).requiresPassphrase) return false;
    return _ref.read(backendSessionProvider) == BackendStatus.ready;
  }

  /// El usuario ha hecho algo: se reinicia la cuenta atrás.
  void noteActivity() {
    if (_throttleWindow?.isActive ?? false) return;
    _throttleWindow = Timer(_throttle, () {});

    // El pulso se emite siempre, aunque no haya bóveda que bloquear: la
    // mascota lo necesita igual.
    activity.value++;

    if (!_isRelevant) return;

    final Duration delay = _idleDelay;
    _idleTimer?.cancel();
    if (delay == Duration.zero) return;

    _idleTimer = Timer(delay, _lockNow);
  }

  /// La app se va a segundo plano.
  Future<void> onBackgrounded() async {
    _idleTimer?.cancel();
    if (!_isRelevant) return;
    // Antes de cerrar, se vuelca lo que quede pendiente: si no, el bloqueo se
    // llevaría por delante un gasto anotado dos segundos antes.
    await _ref.read(backendSessionProvider.notifier).flush();
    await _ref.read(backendSessionProvider.notifier).lock();
  }

  void _lockNow() {
    if (!_isRelevant) return;
    unawaited(_ref.read(backendSessionProvider.notifier).lock());
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _throttleWindow?.cancel();
    _throttleWindow = null;
    activity.dispose();
  }
}

final Provider<AutoLockController> autoLockProvider =
    Provider<AutoLockController>((Ref ref) {
  final AutoLockController controller = AutoLockController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Envuelve la app para detectar actividad del usuario.
///
/// Se usa un [Listener] y no un `GestureDetector`: el primero ve los eventos
/// del puntero en la fase de captura, sin competir con los gestos de los
/// widgets de dentro. Con un `GestureDetector` habría que pelear con la arena
/// de gestos y algunos toques no llegarían.
class ActivityDetector extends ConsumerStatefulWidget {
  const ActivityDetector({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ActivityDetector> createState() => _ActivityDetectorState();
}

class _ActivityDetectorState extends ConsumerState<ActivityDetector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(autoLockProvider).noteActivity();
    });
  }

  void _wake([Object? _]) => ref.read(autoLockProvider).noteActivity();

  @override
  Widget build(BuildContext context) {
    // Al desbloquear la bóveda hay que arrancar la cuenta atrás, aunque el
    // usuario no toque nada más.
    ref.listen<BackendStatus>(backendSessionProvider, (_, BackendStatus next) {
      if (next == BackendStatus.ready) _wake();
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _wake,
      onPointerMove: _wake,
      onPointerSignal: _wake,
      child: widget.child,
    );
  }
}
