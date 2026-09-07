import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/di/providers.dart';
import 'core/error/failures.dart';
import 'core/theme/app_colors.dart';
import 'core/i18n/cjk_font_loader.dart';
import 'core/theme/app_theme.dart';
import 'data/backend/app_backend.dart';
import 'presentation/providers/auto_lock_provider.dart';
import 'presentation/providers/bootstrap_provider.dart';
import 'presentation/providers/lock_provider.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/screens/lock/vault_gate_screen.dart';
import 'presentation/widgets/common.dart';

/// Raiz de la aplicación.
class HannahsWalletApp extends StatelessWidget {
  const HannahsWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Un unico tema, el claro. La app se ve igual en todos los dispositivos,
      // sin depender de los ajustes del sistema.
      theme: AppTheme.light(),
      // La app es solo en espanol: fijar el locale evita que los selectores de
      // fecha del sistema salgan en ingles en un dispositivo configurado en
      // otro idioma, cosa que chocaria con el resto de la interfaz.
      locale: const Locale('es', 'ES'),
      supportedLocales: const <Locale>[Locale('es', 'ES')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Toda la app va dentro del detector de actividad: cualquier toque
      // reinicia la cuenta atrás del bloqueo automático.
      home: const ActivityDetector(child: _AppGate()),
    );
  }
}

/// Decide que se ve: carga, error, bóveda cerrada, bloqueo o la app.
///
/// Concentra las cinco posibilidades en un sitio para que ninguna pantalla
/// tenga que preguntarse si los datos ya están accesibles.
class _AppGate extends ConsumerStatefulWidget {
  const _AppGate();

  @override
  ConsumerState<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<_AppGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: _onPaused,
      onResume: () => ref.read(appLockProvider.notifier).onResumed(),
      // `onDetach` es la última llamada antes de que el proceso muera; en web
      // corresponde a cerrar la pestana. Es la última oportunidad de volcar lo
      // que siga esperando en la ventana de agrupación de escrituras.
      onDetach: () => unawaited(ref.read(backendSessionProvider.notifier).flush()),
    );
    _warmUpCjkFont();
  }

  /// Pide la fuente china en cuanto hay algo pintado.
  ///
  /// Se lanza DESPUÉS del primer frame y sin `await`: son 8,3 MB y esperarlos
  /// antes de enseñar nada retrasaría el arranque varios segundos para quien
  /// no va a escribir un solo carácter chino. Al llegar, Flutter rehace el
  /// layout y los caracteres aparecen solos.
  void _warmUpCjkFont() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tres segundos de margen: son 8 MB, y pedirlos nada mas pintar compite
      // por el ancho de banda con el motor y el codigo de la app, que si hacen
      // falta para que se pueda tocar algo. Con este retraso la app ya esta
      // usable cuando empieza la descarga.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3))
            .then((_) => CjkFontLoader.ensureLoaded()),
      );
    });
  }

  void _onPaused() {
    ref.read(appLockProvider.notifier).onPaused();
    // Al irse a segundo plano se persiste Y se cierra la bóveda. En iOS el
    // sistema puede descargar la app sin previo aviso, así que un gasto
    // anotado hace dos segundos no puede depender de un temporizador
    // pendiente; y dejar la sesión abierta mientras el móvil anda por ahí
    // anularía el cifrado, que solo protege los datos en reposo.
    unawaited(ref.read(autoLockProvider).onBackgrounded());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BootstrapResult> bootstrap = ref.watch(appBootstrapProvider);

    return switch (bootstrap) {
      AsyncData<BootstrapResult>() => const _VaultGate(),
      AsyncError<BootstrapResult>(:final Object error) => Scaffold(
          body: SafeArea(
            child: FailureView(
              message: error is AppFailure
                  ? error.message
                  : 'No se pudo preparar el almacen cifrado.\n$error',
              onRetry: () => ref.invalidate(appBootstrapProvider),
            ),
          ),
        ),
      _ => const _SplashScreen(),
    };
  }
}

/// Primera puerta: el almacen de datos.
///
/// En la PWA aquí se pide la contraseña maestra. En móvil este paso es
/// transparente, porque la clave sale del Keychain y el estado ya llega
/// `ready`.
class _VaultGate extends ConsumerWidget {
  const _VaultGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackendStatus status = ref.watch(backendSessionProvider);

    return switch (status) {
      BackendStatus.needsSetup ||
      BackendStatus.locked =>
        VaultGateScreen(mode: status),
      BackendStatus.ready => const _SessionGate(),
    };
  }
}

/// Segunda puerta: la sesión de datos ya esta abierta, se completa el arranque
/// (ajustes y movimientos recurrentes) y después se aplica el bloqueo de
/// pantalla si lo hay.
class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> session = ref.watch(sessionBootstrapProvider);

    return switch (session) {
      AsyncData<int>() => const _LockGate(),
      AsyncError<int>(:final Object error) => Scaffold(
          body: SafeArea(
            child: FailureView(
              message: error is AppFailure
                  ? error.message
                  : 'No se pudieron cargar tus datos.\n$error',
              onRetry: () => ref.invalidate(sessionBootstrapProvider),
            ),
          ),
        ),
      _ => const _SplashScreen(),
    };
  }
}

/// Tercera puerta: bloqueo de pantalla (solo móvil).
class _LockGate extends ConsumerWidget {
  const _LockGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LockStatus status = ref.watch(appLockProvider);

    return switch (status) {
      LockStatus.locked => const LockScreen(),
      LockStatus.unlocked => const HomeShell(),
      LockStatus.unknown => const _SplashScreen(),
    };
  }
}

/// Splash mientras se prepara el almacen.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(30),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.pets_rounded,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(AppConstants.appName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Preparando tus cuentas...', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 26),
            SizedBox(
              width: 130,
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
