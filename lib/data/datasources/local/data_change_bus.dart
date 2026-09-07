import 'dart:async';

/// Aviso de "algo ha cambiado en la base".
///
/// SQLite no tiene notificaciones nativas: si el dashboard esta suscrito a una
/// consulta y otra pantalla inserta un gasto, nadie se entera. La alternativa
/// habitual es sondear cada N segundos, que gasta batería y aun así va tarde.
///
/// Aquí cada repositorio dispara [notify] después de escribir, y los providers
/// de Riverpod se invalidan al recibir el pulso. Es un bus deliberadamente
/// tonto: no dice QUE cambio, solo que hay que releer. Con el volumen de datos
/// de una app de finanzas personales (miles de filas, no millones) releer es
/// mas barato que mantener un sistema de invalidación por tabla.
class DataChangeBus {
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  /// Se emite tras cada escritura confirmada.
  Stream<void> get changes => _controller.stream;

  void notify() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  Future<void> dispose() => _controller.close();
}
