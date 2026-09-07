/// Jerarquia de errores de dominio.
///
/// Las capas de datos traducen excepciones concretas (SQLite, ficheros,
/// plataforma) a estos tipos para que la UI nunca dependa de un paquete.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// La base cifrada no pudo abrirse o la clave no es valida.
class DatabaseFailure extends AppFailure {
  const DatabaseFailure(super.message, {super.cause, super.stackTrace});
}

/// Fallo generando, leyendo o rotando material criptográfico.
class SecurityFailure extends AppFailure {
  const SecurityFailure(super.message, {super.cause, super.stackTrace});
}

/// El backup no es un JSON valido de esta app, o su versión es incompatible.
class BackupFormatFailure extends AppFailure {
  const BackupFormatFailure(super.message, {super.cause, super.stackTrace});
}

/// Fallo de entrada/salida al escribir o leer el fichero de backup.
class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause, super.stackTrace});
}

/// Regla de negocio incumplida (importe cero, cartera inexistente, etc.).
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause, super.stackTrace});
}

/// El usuario no supero el bloqueo biométrico o el PIN.
class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.cause, super.stackTrace});
}
