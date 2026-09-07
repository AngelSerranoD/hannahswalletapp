import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/cjk_font_loader.dart';
import 'app_colors.dart';

/// Tema de la app: minimalista, de curvas suaves y en rosa, como Flowfy.
///
/// **Un solo tema, el claro.** No hay variante oscura ni selector: la app se ve
/// igual en todos los dispositivos, con los colores tomados de Flowfy. Eso
/// simplifica el código -ningún color hay que resolverlo según el brillo del
/// sistema- y, sobre todo, hace que los contrastes verificados sean los que se
/// ven siempre, y no solo en uno de los dos modos.
///
/// Todo el redondeo de la app sale de [radiusL] / [radiusM] para que las
/// tarjetas, los campos y los diálogos compartan la misma curvatura.
abstract final class AppTheme {
  static const double radiusS = 12;
  static const double radiusM = 18;
  static const double radiusL = 28;
  static const double radiusXL = 36;

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 8);

  /// Cuerpo de la app: Archivo.
  ///
  /// Sustituye a Coolvetica, cuya licencia gratuita excluye expresamente las
  /// apps y los webfonts. Se eligio comparando ambas al tamano real de uso:
  /// es la que mas se le acerca en compacidad y peso (Inter resulto mas ancha
  /// y Manrope mas ligera). Licencia SIL OFL, sin restricciones de uso.
  static const String bodyFont = 'Archivo';

  /// Titulos: Pinyon Script.
  ///
  /// Sustituye a CandleScript, cuya version demo solo traia 56 glifos y
  /// dibujaba su propio nombre en lugar de los caracteres que le faltaban.
  /// Pinyon Script cubre el latino completo (757 glifos), asi que se puede
  /// aplicar a CUALQUIER titulo: ya no hace falta comprobar antes si el texto
  /// "cabe" en la fuente. Licencia SIL OFL.
  static const String titleFont = 'PinyonScript';

  /// Devuelve [base] con la fuente caligrafica de titulo.
  static TextStyle? titleStyle(String text, TextStyle? base) =>
      base?.copyWith(fontFamily: titleFont);

  static ThemeData light() {
    const ColorScheme scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.secondarySoft,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.income,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerHighest: AppColors.surfaceAlt,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
    );

    final TextTheme text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      // Roboto para el latino y Noto Sans SC para lo que no cubra.
      //
      // El orden importa: Flutter usa la primera fuente que tenga el glifo, así
      // que las tildes y los símbolos de moneda siguen saliendo de Roboto y
      // solo los caracteres chinos caen en la de reserva. Sin esta línea, un
      // nombre de categoría en chino se vería como rectángulos vacíos.
      fontFamily: bodyFont,
      // Lo que Archivo no cubra -el chino- cae en Noto Sans SC.
      fontFamilyFallback: const <String>[CjkFontLoader.family],
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        // Iconos oscuros en la barra de estado: el fondo siempre es claro.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusL)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.paper),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: AppColors.outline),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final Color primary = scheme.onSurface;
    final Color secondary = scheme.onSurfaceVariant;
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: primary),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: secondary),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.35, color: secondary),
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: secondary,
      ),
    );
  }
}
