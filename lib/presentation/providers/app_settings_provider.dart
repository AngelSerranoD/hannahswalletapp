import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../domain/repositories/repositories.dart';

/// Preferencias de la app, ya tipadas.
class AppSettings extends Equatable {
  const AppSettings({
    this.currencyCode = 'EUR',
    this.lockEnabled = false,
    this.biometricEnabled = false,
    this.mascotEnabled = true,
    this.onboardingDone = false,
    this.autoLockMinutes = 3,
  });

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      currencyCode: map[AppConstants.kCurrencyCode] ?? 'EUR',
      lockEnabled: _bool(map[AppConstants.kLockEnabled]),
      biometricEnabled: _bool(map[AppConstants.kBiometricEnabled]),
      mascotEnabled: _bool(map[AppConstants.kMascotEnabled], fallback: true),
      onboardingDone: _bool(map[AppConstants.kOnboardingDone]),
      autoLockMinutes:
          int.tryParse(map[AppConstants.kAutoLockMinutes] ?? '') ?? 3,
    );
  }

  final String currencyCode;
  final bool lockEnabled;
  final bool biometricEnabled;
  final bool mascotEnabled;
  final bool onboardingDone;

  /// Minutos de inactividad tras los que la app se bloquea sola. 0 = nunca.
  ///
  /// Por defecto 3: suficiente para no molestar mientras se anota un gasto, y
  /// lo bastante corto para que dejar el móvil encima de la mesa no deje las
  /// cuentas a la vista.
  final int autoLockMinutes;

  static bool _bool(String? raw, {bool fallback = false}) {
    if (raw == null) return fallback;
    return raw.toLowerCase() == 'true' || raw == '1';
  }

  AppSettings copyWith({
    String? currencyCode,
    bool? lockEnabled,
    bool? biometricEnabled,
    bool? mascotEnabled,
    bool? onboardingDone,
    int? autoLockMinutes,
  }) {
    return AppSettings(
      currencyCode: currencyCode ?? this.currencyCode,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      mascotEnabled: mascotEnabled ?? this.mascotEnabled,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        currencyCode,
        lockEnabled,
        biometricEnabled,
        mascotEnabled,
        onboardingDone,
        autoLockMinutes,
      ];
}

/// Estado de ajustes, respaldado por la tabla `app_settings` (cifrada).
///
/// Se expone como [AsyncNotifier] porque la primera lectura necesita abrir la
/// base. Cada `set` escribe en disco y actualiza el estado en memoria de una
/// vez, sin esperar a releer: la UI responde al instante y la base ya queda
/// consistente.
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final SettingsRepository repo = ref.watch(settingsRepositoryProvider);
    return AppSettings.fromMap(await repo.getAll());
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> setCurrency(String code) async {
    await _repo.set(AppConstants.kCurrencyCode, code);
    _patch((AppSettings s) => s.copyWith(currencyCode: code));
  }

  Future<void> setLockEnabled(bool value) async {
    await _repo.setBool(AppConstants.kLockEnabled, value);
    // Desactivar el bloqueo apaga también la biometría: dejarla marcada haría
    // creer que algo sigue protegiendo la app cuando no es así.
    _patch((AppSettings s) => s.copyWith(
          lockEnabled: value,
          biometricEnabled: value && s.biometricEnabled,
        ));
    if (!value) {
      await _repo.setBool(AppConstants.kBiometricEnabled, false);
    }
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _repo.setBool(AppConstants.kBiometricEnabled, value);
    _patch((AppSettings s) => s.copyWith(biometricEnabled: value));
  }

  Future<void> setMascotEnabled(bool value) async {
    await _repo.setBool(AppConstants.kMascotEnabled, value);
    _patch((AppSettings s) => s.copyWith(mascotEnabled: value));
  }

  /// Minutos de inactividad antes del bloqueo automático. 0 = nunca.
  Future<void> setAutoLockMinutes(int minutes) async {
    await _repo.set(AppConstants.kAutoLockMinutes, '$minutes');
    _patch((AppSettings s) => s.copyWith(autoLockMinutes: minutes));
  }

  Future<void> markOnboardingDone() async {
    await _repo.setBool(AppConstants.kOnboardingDone, true);
    _patch((AppSettings s) => s.copyWith(onboardingDone: true));
  }

  void _patch(AppSettings Function(AppSettings) update) {
    final AppSettings? current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData<AppSettings>(update(current));
  }
}

final AsyncNotifierProvider<AppSettingsNotifier, AppSettings>
    appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
        AppSettingsNotifier.new);

/// Atajo sincrono con valores por defecto mientras carga.
///
/// Evita que toda la app tenga que tratar `AsyncValue` solo para saber el
/// tema o el simbolo de la moneda.
final Provider<AppSettings> settingsSnapshotProvider =
    Provider<AppSettings>((Ref ref) =>
        ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings());

/// Código de moneda activo. Lo consultan casi todos los widgets que pintan
/// importes, de ahi que tenga su propio provider granular.
final Provider<String> currencyProvider =
    Provider<String>((Ref ref) => ref.watch(settingsSnapshotProvider).currencyCode);
