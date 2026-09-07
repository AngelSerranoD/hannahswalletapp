/*
 * Hannah's Wallet
 * Copyright (c) 2026 Ángel Serrano Domínguez. Todos los derechos reservados.
 *
 * Obra original de Ángel Serrano Domínguez <angelsd7704@gmail.com>.
 * Prohibida su copia, modificación o distribución sin autorización expresa
 * y por escrito del autor. Véase el archivo LICENSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Punto de entrada de Hannah's Wallet.
///
/// La app es OFFLINE-FIRST por diseno: no hay cliente HTTP, ni SDK de
/// analitica, ni servidor. Todo lo que se anota vive cifrado con SQLCipher en
/// el almacenamiento privado del dispositivo y solo sale de ahi si el usuario
/// exporta una copia a mano.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Solo vertical: los formularios de importe y el teclado del PIN están
  // pensados para una columna, y en horizontal quedan incomodos.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Barra de estado transparente: la cabecera del dashboard pinta su propio
  // degradado hasta arriba del todo.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: HannahsWalletApp()));
}
