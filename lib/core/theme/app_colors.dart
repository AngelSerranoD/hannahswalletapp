import 'package:flutter/material.dart';

/// Paleta del estanque: verdes, beige y rosa palo. Tema claro único.
///
/// ### Los cinco colores base
///
/// ```
/// #0A3323  verde oscuro    Dark green
/// #839958  verde musgo     Moss green
/// #F7F4D5  beige           Beige
/// #D3968C  rosa palo       Rosy brown
/// #105666  verde noche     Midnight green
/// ```
///
/// ### Qué puede hacer cada uno, medido
///
/// Sobre el beige del fondo, solo dos de los cuatro colores restantes sirven
/// para TEXTO: el verde oscuro (12,5:1) y el verde noche (7,4:1). El musgo se
/// queda en 2,8:1 y el rosa palo en 2,2:1 — por debajo incluso del mínimo para
/// texto grande.
///
/// Eso no los descarta, los coloca: son colores de RELLENO. Como fondo de un
/// distintivo o de una barra, con el verde oscuro escrito encima, dan 4,4:1 y
/// 5,6:1 respectivamente, que sí es legible. Usarlos al revés -texto musgo
/// sobre beige- sería un error de contraste difícil de ver en el monitor del
/// que diseña y muy evidente al sol.
///
/// ### Tonos derivados
///
/// La paleta trae un solo color claro, así que las tarjetas se derivan
/// aclarando el beige un 55 % hacia el blanco: sin eso, tarjeta y fondo serían
/// el mismo color y las tarjetas desaparecerían. Los bordes y los tonos de
/// aviso salen igual, mezclando los cinco entre sí.
///
/// ### El color sigue sin ser el único portador
///
/// Aunque esta paleta sí tiene matices distinguibles, se conservan los
/// recursos no cromáticos que ya estaban: signo `+` / `−` y peso para ingresos
/// frente a gastos, y trama diagonal para el presupuesto rebasado. Funcionan
/// para quien no distingue el verde del rosa, y no cuestan nada mantener.
abstract final class AppColors {
  // -------------------------------------------------------- Colores base

  /// Verde oscuro. Texto principal y acción primaria.
  static const Color darkGreen = Color(0xFF0A3323);

  /// Verde musgo. Relleno: distintivos, barras, acentos sin texto pequeño.
  static const Color moss = Color(0xFF839958);

  /// Beige. El fondo de la app.
  static const Color beige = Color(0xFFF7F4D5);

  /// Rosa palo. Relleno de avisos y de la trama de presupuesto rebasado.
  static const Color rosyBrown = Color(0xFFD3968C);

  /// Verde noche. Acción secundaria e ingresos.
  static const Color midnight = Color(0xFF105666);

  // ---------------------------------------------------------- Tipografía

  /// Tinta de la marca. 12,5:1 sobre el fondo.
  static const Color ink = darkGreen;
  static const Color textPrimary = darkGreen;

  /// Texto secundario. 7,4:1.
  static const Color textSecondary = midnight;

  /// Texto terciario: notas al pie. 3,7:1, el límite de lo legible; no se usa
  /// para nada que haya que leer con atención.
  static const Color textTertiary = Color(0xFF558587);

  /// Elementos desactivados. Bajo contraste a propósito: indica que algo NO se
  /// puede usar.
  static const Color textDisabled = Color(0xFF9AAFA4);

  // ---------------------------------------------------------- Superficies

  static const Color background = beige;

  /// Tarjetas: beige aclarado, lo justo para que floten sobre el fondo.
  static const Color surface = Color(0xFFFBFAEC);

  /// Superficie hundida: campos de texto y fondo de las barras.
  static const Color surfaceAlt = Color(0xFFE4E5C7);

  static const Color outline = Color(0xFFCCD1B5);
  static const Color outlineSoft = Color(0xFFE4E5C7);

  /// Beige sobre superficies oscuras: texto de botones y snackbars.
  static const Color paper = beige;

  // ---------------------------------------------------- Papeles semánticos

  /// Acción principal: botones, FAB.
  static const Color primary = darkGreen;
  static const Color primarySoft = Color(0xFFE4E5C7);

  /// Acción secundaria.
  static const Color secondary = midnight;
  static const Color secondarySoft = Color(0xFFBFD6D3);

  /// Ingresos. El verde noche los separa del texto corriente sin gritar; el
  /// signo `+` y la negrita hacen el resto.
  static const Color income = midnight;

  /// Relleno de barras de ingreso.
  static const Color incomeSoft = moss;

  /// Peligro: rosa palo oscurecido hasta 5,2:1 para poder escribir con él.
  /// El rosa original queda para los rellenos ([dangerSoft]).
  static const Color danger = Color(0xFF8A4F42);
  static const Color dangerSoft = rosyBrown;

  /// Aviso: musgo oscurecido hasta 5,0:1.
  static const Color warning = Color(0xFF537043);
  static const Color warningSoft = moss;

  /// Escala de las categorías.
  ///
  /// Los cinco colores de la paleta más un par de mezclas, ordenados para que
  /// dos vecinos nunca compartan matiz: verde oscuro, rosa, verde noche,
  /// musgo, verde medio y verde agua. Aquí la distinción es CROMÁTICA y no de
  /// luminosidad, que es lo que permite tener seis niveles distinguibles en
  /// una paleta con un solo tono claro.
  static const List<int> categoryPalette = <int>[
    0xFF0A3323, // verde oscuro
    0xFFD3968C, // rosa palo
    0xFF105666, // verde noche
    0xFF839958, // musgo
    0xFF4D6B40, // verde medio
    0xFF789D98, // verde agua
  ];
}
