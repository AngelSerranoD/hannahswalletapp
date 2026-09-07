import 'app_backend.dart';
import 'backend_factory_stub.dart'
    if (dart.library.io) 'backend_factory_io.dart'
    if (dart.library.js_interop) 'backend_factory_web.dart' as impl;

/// Crea el backend que corresponde a la plataforma actual.
///
/// El import condicional de arriba es la pieza clave de todo el montaje: hace
/// que el compilador NI SIQUIERA VEA el fichero de la otra plataforma. Sin el,
/// el build web arrastraría `sqflite_sqlcipher` -que no tiene implementación
/// web- y fallaria al compilar; y el build de iOS cargaria el código de
/// IndexedDB, que alli no pinta nada.
///
///   * `dart.library.io`          -> móvil y escritorio -> NativeBackend
///   * `dart.library.js_interop`  -> navegador          -> WebBackend
AppBackend createAppBackend() => impl.createBackend();
