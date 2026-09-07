import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/di/providers.dart';
import '../../../data/services/lock_gate.dart';
import '../../providers/lock_provider.dart';

/// Pantalla de desbloqueo: biometría primero, PIN de respaldo.
///
/// Se intenta la biometría nada mas entrar, sin pedir que el usuario pulse
/// nada: el gesto natural al abrir una app protegida es poner el dedo.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;
  bool _biometricTried = false;

  /// Intentos fallidos seguidos de PIN.
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    if (_biometricTried) return;
    _biometricTried = true;

    final LockGate gate = ref.read(lockGateProvider);
    if (!await gate.isBiometricAvailable()) return;

    final BiometricResult result = await gate.authenticate();
    if (!mounted) return;
    if (result == BiometricResult.success) {
      ref.read(appLockProvider.notifier).markUnlocked();
    }
  }

  Future<void> _submitPin() async {
    if (_pin.length < 4 || _checking) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    final bool ok = await ref.read(lockGateProvider).verifyPin(_pin);
    if (!mounted) return;

    if (ok) {
      ref.read(appLockProvider.notifier).markUnlocked();
      return;
    }

    _failedAttempts++;
    HapticFeedback.heavyImpact();
    setState(() {
      _checking = false;
      _pin = '';
      _error = _failedAttempts >= 3
          ? 'PIN incorrecto ($_failedAttempts intentos fallidos).'
          : 'PIN incorrecto.';
    });
  }

  void _push(String digit) {
    if (_pin.length >= 8) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    // Con 4 dígitos se comprueba solo: es la longitud mas habitual y evita
    // tener que buscar el boton de confirmar.
    if (_pin.length == 4) _submitPin();
  }

  void _pop() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasPin = ref.watch(hasPinProvider).valueOrNull ?? false;
    final bool biometricAvailable =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.lock_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(AppConstants.appName, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  'Tus cuentas están cifradas en este dispositivo.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                if (hasPin) ...<Widget>[
                  _PinDots(length: _pin.length, error: _error != null),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 22,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.danger),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _Keypad(
                    onDigit: _push,
                    onBackspace: _pop,
                    onBiometric: biometricAvailable
                        ? () {
                            _biometricTried = false;
                            _tryBiometrics();
                          }
                        : null,
                  ),
                ] else ...<Widget>[
                  // Bloqueo activado pero sin PIN: solo queda la biometría.
                  FilledButton.icon(
                    onPressed: () {
                      _biometricTried = false;
                      _tryBiometrics();
                    },
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Desbloquear'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puntos que representan los dígitos introducidos.
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.error});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(
        // Se pintan al menos cuatro huecos, y crecen si el PIN es mas largo.
        length > 4 ? length : 4,
        (int i) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < length
                ? (error ? AppColors.danger : scheme.primary)
                : scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

/// Teclado numerico propio.
///
/// No se usa un `TextField` con teclado del sistema porque el teclado nativo
/// tapa media pantalla, permite pegar desde el portapapeles y guarda el
/// historial de escritura. Para un PIN, todo eso sobra.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
        children: <Widget>[
          for (int i = 1; i <= 9; i++)
            _KeypadButton(label: '$i', onTap: () => onDigit('$i')),
          if (onBiometric != null)
            _KeypadButton(icon: Icons.fingerprint_rounded, onTap: onBiometric!)
          else
            const SizedBox.shrink(),
          _KeypadButton(label: '0', onTap: () => onDigit('0')),
          _KeypadButton(icon: Icons.backspace_outlined, onTap: onBackspace),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, this.label, this.icon});

  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant)
              : Text(label!, style: theme.textTheme.headlineSmall),
        ),
      ),
    );
  }
}
