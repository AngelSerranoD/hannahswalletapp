import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../core/di/providers.dart';
import '../../core/utils/date_range.dart';
import '../../data/backend/app_backend.dart';
import '../widgets/mascot/kitty_mascot_widget.dart';
import 'app_settings_provider.dart';

/// Lo que ocurre entre el splash y la primera pantalla.
class BootstrapResult {
  const BootstrapResult({required this.status});

  /// Estado del almacen tras el arranque: si es `needsSetup` o `locked`, la UI
  /// ensena la pantalla de contraseña antes que nada.
  final BackendStatus status;
}

/// Arranque de la app, en el orden en que las cosas se necesitan.
///
/// Se hace en un único provider para que la pantalla de carga tenga UN estado
/// que observar, y para que un fallo al abrir el almacen se muestre como una
/// pantalla de error explicada en vez de como una excepcion en rojo.
final FutureProvider<BootstrapResult> appBootstrapProvider =
    FutureProvider<BootstrapResult>((Ref ref) async {
  // 1. Datos de localización de `intl`. Sin esto, cualquier `DateFormat` con
  //    locale 'es_ES' lanza LocaleDataException en el primer render.
  await initializeDateFormatting(AppDates.locale);

  // 2. Preparar el almacen. En móvil abre y crea la base cifrada; en la PWA
  //    solo comprueba si ya existe bóveda, SIN descifrarla (para eso hace
  //    falta la contraseña, que aún no se ha pedido).
  final BackendStatus status =
      await ref.read(backendSessionProvider.notifier).initialize();

  // 3. Parsear las animaciones del gato fuera del camino critico del primer
  //    frame del dashboard.
  KittyCompositions.warmUp();

  return BootstrapResult(status: status);
});

/// Segunda fase del arranque: lo que solo se puede hacer con los datos ya
/// accesibles.
///
/// Va aparte de [appBootstrapProvider] porque en la PWA estas tareas no pueden
/// ejecutarse hasta que el usuario introduce la contraseña. Se observa
/// [backendSessionProvider] para que se dispare justo al desbloquear.
final FutureProvider<int> sessionBootstrapProvider =
    FutureProvider<int>((Ref ref) async {
  final BackendStatus status = ref.watch(backendSessionProvider);
  if (status != BackendStatus.ready) return 0;

  // Los ajustes primero: el tema y la moneda deben estar listos para el primer
  // frame, o se veria un parpadeo de claro a oscuro.
  await ref.read(appSettingsProvider.future);

  // Generar los movimientos recurrentes vencidos mientras la app estuvo
  // cerrada, para que el saldo salga correcto desde el principio.
  return ref.read(recurringRepositoryProvider).materializeDue();
});
