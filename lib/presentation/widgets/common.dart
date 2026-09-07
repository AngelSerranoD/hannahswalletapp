import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/icon_catalog.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/transaction_entity.dart';

/// Tarjeta base de toda la app: superficie, curva y borde suave.
class SoftCard extends StatelessWidget {
  const SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(AppTheme.radiusL);

    return Material(
      color: color ?? scheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Título con la fuente caligráfica, cuando el texto lo permite.
///
/// Ver [AppTheme.titleStyle]: la versión demo de CandleScript solo tiene
/// letras sin acentos, y para lo que le falta dibuja el nombre de la fuente.
/// Este widget decide por texto completo, así que un título nunca sale con
/// media palabra en una tipografía y media en otra.
class AppTitle extends StatelessWidget {
  const AppTitle(this.text, {this.style, this.textAlign, super.key});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final TextStyle? base = style ?? Theme.of(context).textTheme.titleLarge;
    return Text(
      text,
      style: AppTheme.titleStyle(text, base),
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Título de sección con acción opcional a la derecha.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: <Widget>[
          Expanded(child: AppTitle(title)),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Importe con el signo, el peso y el tono que le corresponden.
///
/// Centraliza la regla de la app: en una paleta sin color, lo que distingue un
/// ingreso de un gasto es el SIGNO (`+` / `−`) y el PESO tipográfico, no el
/// matiz. El ingreso va en tinta y en negrita porque es lo excepcional en una
/// lista de gastos; el gasto, en peso normal, para que el historial no se
/// convierta en un muro de negritas.
class AmountText extends StatelessWidget {
  const AmountText({
    required this.cents,
    required this.currencyCode,
    this.type,
    this.style,
    this.showSign = true,
    super.key,
  });

  final int cents;
  final String currencyCode;
  final TransactionType? type;
  final TextStyle? style;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Sin color, la diferencia entre entrar y salir dinero la marcan el SIGNO
    // y el PESO. El ingreso va en tinta plena y en negrita: destaca en la
    // lista. El gasto, que es lo habitual, va en peso normal para no convertir
    // el historial en un muro de negritas.
    final Color color = switch (type) {
      TransactionType.income => AppColors.income,
      TransactionType.transfer => AppColors.textTertiary,
      TransactionType.expense => AppColors.textPrimary,
      null => cents < 0 ? AppColors.textPrimary : AppColors.ink,
    };

    final FontWeight weight = switch (type) {
      TransactionType.income => FontWeight.w700,
      TransactionType.transfer => FontWeight.w500,
      _ => FontWeight.w600,
    };

    // El menos es U+2212 (−), no el guion del teclado: tiene el mismo ancho
    // que el `+` y la misma altura que las cifras, así que las columnas de
    // importes quedan alineadas en vez de bailar.
    final String prefix = switch (type) {
      TransactionType.income => '+',
      TransactionType.expense => '−',
      _ => '',
    };

    return Text(
      '$prefix${Money.format(cents.abs(), currencyCode: currencyCode)}',
      style: (style ?? theme.textTheme.titleMedium)?.copyWith(
        color: color,
        fontWeight: weight,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Distintivo con el icono de una categoría o cartera.
///
/// En monocromo el distintivo se INVIERTE: el tono de la categoría va al
/// fondo y el icono se pinta en blanco o en tinta, el que contraste con él.
/// Con el planteamiento anterior -fondo del color al 16 %, icono del color- un
/// gris claro daba 1,4:1 y el icono desaparecía. Así, además, las categorías
/// se distinguen por la intensidad del distintivo, que es mucho más visible
/// que el tono de un icono pequeño.
class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.iconCode,
    required this.colorValue,
    this.size = 44,
    this.fallbackIcon,
    super.key,
  });

  final int? iconCode;
  final int? colorValue;
  final double size;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final Color badge =
        colorValue != null ? Color(colorValue!) : AppColors.textSecondary;
    final IconData icon = iconCode != null
        ? IconCatalog.resolve(iconCode!)
        : (fallbackIcon ?? IconCatalog.fallback);

    // `computeLuminance` decide si el icono va claro u oscuro. El umbral 0,5
    // es el punto en que el blanco deja de contrastar mejor que el negro.
    final Color foreground =
        badge.computeLuminance() > 0.5 ? AppColors.ink : AppColors.paper;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badge,
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: foreground),
    );
  }
}

/// Estado vacío con icono, mensaje y acción opcional.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pantalla de error legible para los fallos de la capa de datos.
class FailureView extends StatelessWidget {
  const FailureView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded,
                size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Barra de progreso redondeada con color según lo consumido.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required this.ratio,
    this.height = 10,
    this.color,
    super.key,
  });

  /// Fraccion consumida. Se recorta a `[0, 1]` para pintar.
  final double ratio;
  final double height;
  final Color? color;

  /// Tono del relleno según lo consumido: verde noche holgado, verde de aviso
  /// ajustado, terracota pasado.
  ///
  /// Los tres se han elegido con contraste suficiente para servir TAMBIÉN de
  /// texto, porque este color pinta además el "87 %" que acompaña a la barra.
  /// Y el salto real -haberse pasado- no se fía solo del matiz: lo marca la
  /// trama diagonal de [_StripePainter], que funciona para quien no distingue
  /// el verde del rojo.
  static Color colorFor(double ratio) {
    if (ratio >= 0.9) return AppColors.danger;
    if (ratio >= 0.7) return AppColors.warning;
    return AppColors.income;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double value = ratio.clamp(0.0, 1.0);
    final bool overspent = ratio > 1.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double animated, _) {
          final Color fill = color ?? colorFor(ratio);

          if (!overspent) {
            return LinearProgressIndicator(
              value: animated,
              minHeight: height,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(fill),
            );
          }

          // Rebasado: barra llena y rayada. La trama es el sustituto del rojo
          // que sigue funcionando sin color, y además se distingue al instante
          // de una barra simplemente llena al 100 %.
          return CustomPaint(
            painter: _StripePainter(color: fill),
            child: SizedBox(height: height, width: double.infinity),
          );
        },
      ),
    );
  }
}

/// Trama diagonal para la barra de presupuesto rebasado.
///
/// Sustituye al rojo de alarma. Una trama se percibe sin depender de la visión
/// del color, se distingue de una barra llena aunque las dos estén al 100 %, y
/// sigue leyéndose igual en una captura en blanco y negro.
class _StripePainter extends CustomPainter {
  const _StripePainter({required this.color});

  final Color color;

  /// Separación entre rayas. Suficiente para que se vean como trama y no como
  /// un gris uniforme al tamaño real de la barra (10 px de alto).
  static const double _gap = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()..color = color.withValues(alpha: 0.28);
    canvas.drawRect(Offset.zero & size, background);

    final Paint stripe = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;

    // Diagonales a 45 grados. Se empieza en -size.height para que la primera
    // raya entre por la esquina superior izquierda y no quede un hueco.
    for (double x = -size.height; x < size.width; x += _gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => oldDelegate.color != color;
}

/// Fila de etiqueta y valor, usada en resumenes y hojas de detalle.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 16),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }
}

/// Muestra un mensaje de error corto en un snackbar del tema.
void showAppSnack(BuildContext context, String message, {bool isError = false}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
}
