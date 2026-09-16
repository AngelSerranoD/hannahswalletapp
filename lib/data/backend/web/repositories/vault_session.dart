import 'dart:async';

import '../../../datasources/local/data_change_bus.dart';
import '../vault_data.dart';

/// Sesión de la bóveda: datos en memoria mas la escritura diferida a disco.
///
/// Cada cambio marca la bóveda como sucia y programa un guardado. NO se cifra
/// y se escribe en cada pulsacion: re-serializar y re-cifrar el historial
/// completo por cada letra de una nota sería absurdo. Se agrupan los cambios
/// en una ventana corta y se fuerza el volcado en los momentos que importan
/// (al exportar, al bloquear, al mandar la app a segundo plano).
class VaultSession {
  VaultSession({
    required this.data,
    required this.bus,
    required Future<void> Function() persist,
  }) : _persist = persist;

  final VaultData data;
  final DataChangeBus bus;
  final Future<void> Function() _persist;

  Timer? _debounce;
  Future<void>? _inFlight;

  /// Ventana de agrupación de escrituras.
  ///
  /// Medio segundo es suficiente para fundir la rafaga de cambios de un
  /// formulario y lo bastante corto como para que cerrar la pestana justo
  /// después de guardar un gasto no lo pierda.
  static const Duration _debounceWindow = Duration(milliseconds: 500);

  /// Marca cambio: avisa a la UI y programa la escritura.
  void touch() {
    bus.notify();
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, () {
      unawaited(flush());
    });
  }

  /// Escribe ya lo que haya pendiente.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    // Si ya hay un guardado en curso se espera a que acabe antes de lanzar
    // otro: dos escrituras simultaneas sobre el mismo registro de IndexedDB
    // podrían dejar la versión antigua encima de la nueva.
    final Future<void>? pending = _inFlight;
    if (pending != null) await pending;

    final Future<void> job = _persist();
    _inFlight = job;
    try {
      await job;
    } finally {
      _inFlight = null;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}
