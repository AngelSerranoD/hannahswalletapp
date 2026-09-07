import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/backend/web/biometric_unlock.dart';
import 'app_settings_provider.dart';

enum LockStatus {
  /// Aún no se sabe si hay que pedir credenciales (ajustes sin cargar).
  unknown,

  /// Hay que pedir biometría o PIN.
  locked,

  /// Sesión abierta.
  unlocked,
}

/// Estado del bloqueo de pantalla en MOVIL.
///
/// Ojo con no confundir las dos capas:
///
///  * en móvil, la base ya esta descifrada (la clave sale del Keystore) y esto
///    solo tapa la pantalla;
///  * en la PWA no existe este bloqueo: alli lo que hay es la contraseña
///    maestra, sin la cual los datos ni siquiera se pueden leer, y la gestiona
///    [backendSessionProvider].
///
/// Por eso, cuando el bloqueo de pantalla no esta soportado, este notifier
/// devuelve siempre `unlocked`: no tiene nada que proteger que no proteja ya
/// la bóveda.
class AppLockNotifier extends Notifier<LockStatus> {
  @override
  LockStatus build() {
    if (!ref.watch(lockGateProvider).isSupported) return LockStatus.unlocked;

    final AppSettings? value = ref.watch(appSettingsProvider).valueOrNull;
    if (value == null) return LockStatus.unknown;
    if (!value.lockEnabled) return LockStatus.unlocked;

    // SALVAGUARDA: no echar el cerrojo si no hay con qué abrirlo.
    //
    // El ajuste puede llegar en `true` sin credenciales detrás -por ejemplo al
    // restaurar en este móvil un backup hecho en otro dispositivo, o en la
    // PWA-, y entonces la pantalla de bloqueo no ofrecería ninguna forma de
    // entrar. El usuario se quedaría fuera de sus propios datos sin haber
    // hecho nada mal, y sin más salida que borrar la app.
    //
    // Mientras las dos comprobaciones cargan se devuelve `unknown` (splash),
    // que es preferible a enseñar un cerrojo y quitarlo un frame después.
    final bool? hasPin = ref.watch(hasPinProvider).valueOrNull;
    final bool? biometric = ref.watch(biometricAvailableProvider).valueOrNull;
    if (hasPin == null || biometric == null) return LockStatus.unknown;
    if (!hasPin && !biometric) return LockStatus.unlocked;

    // Si ya se habia desbloqueado en esta sesión, un cambio de ajustes no debe
    // volver a echar el cerrojo.
    if (_unlockedThisSession) return LockStatus.unlocked;
    return LockStatus.locked;
  }

  bool _unlockedThisSession = false;

  /// Momento en que la app paso a segundo plano.
  DateTime? _backgroundedAt;

  /// Margen antes de exigir credenciales otra vez.
  ///
  /// Sin margen, cualquier cambio de app -abrir la calculadora para sumar un
  /// ticket, atender una notificacion- obligaría a poner la huella al volver,
  /// y el usuario acabaría desactivando el bloqueo entero. Treinta segundos
  /// cubren ese ir y venir sin dejar la app abierta si el móvil se queda solo.
  static const Duration grace = Duration(seconds: 30);

  void markUnlocked() {
    _unlockedThisSession = true;
    _backgroundedAt = null;
    state = LockStatus.unlocked;
  }

  /// La app se fue a segundo plano: solo se anota el instante.
  void onPaused() {
    if (state == LockStatus.unlocked) {
      _backgroundedAt = DateTime.now();
    }
  }

  /// La app vuelve al primer plano: se echa el cerrojo si paso el margen.
  void onResumed() {
    if (!ref.read(lockGateProvider).isSupported) return;
    final AppSettings? settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings == null || !settings.lockEnabled) return;

    final DateTime? since = _backgroundedAt;
    if (since == null) return;

    if (DateTime.now().difference(since) >= grace) {
      _unlockedThisSession = false;
      _backgroundedAt = null;
      state = LockStatus.locked;
    }
  }

  /// Bloqueo inmediato, desde el boton de Ajustes.
  void lockNow() {
    _unlockedThisSession = false;
    _backgroundedAt = null;
    state = LockStatus.locked;
  }
}

final NotifierProvider<AppLockNotifier, LockStatus> appLockProvider =
    NotifierProvider<AppLockNotifier, LockStatus>(AppLockNotifier.new);

/// `true` si el dispositivo tiene biometría utilizable.
final FutureProvider<bool> biometricAvailableProvider =
    FutureProvider<bool>((Ref ref) => ref.watch(lockGateProvider).isBiometricAvailable());

/// `true` si ya hay un PIN configurado.
final FutureProvider<bool> hasPinProvider = FutureProvider<bool>((Ref ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(lockGateProvider).hasPin();
});

/// `true` cuando el almacen se abre con una contraseña que escribe el usuario
/// (la PWA). La UI lo consulta para decidir que pantalla de acceso mostrar.
final Provider<bool> requiresPassphraseProvider =
    Provider<bool>((Ref ref) => ref.watch(appBackendProvider).requiresPassphrase);

/// Motivo por el que la biometría está o no disponible en este dispositivo.
final FutureProvider<BiometricStatus> vaultBiometricStatusProvider =
    FutureProvider<BiometricStatus>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).diagnoseBiometrics();
});

/// `true` si el usuario ya activó el desbloqueo biométrico de la bóveda.
final Provider<bool> vaultBiometricEnabledProvider = Provider<bool>((Ref ref) {
  ref.watch(backendSessionProvider);
  return ref.watch(appBackendProvider).hasBiometricUnlock;
});

