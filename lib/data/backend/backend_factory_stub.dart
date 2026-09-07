import 'app_backend.dart';

/// Nunca se ejecuta: existe solo para que el import condicional tenga un
/// destino por defecto cuando el analizador resuelve el fichero sin saber la
/// plataforma. Si esto llegara a lanzarse, es que la app corre en un entorno
/// que no es ni nativo ni navegador.
AppBackend createBackend() => throw UnsupportedError(
      'Hannah\'s Wallet no tiene backend de datos para esta plataforma.',
    );
