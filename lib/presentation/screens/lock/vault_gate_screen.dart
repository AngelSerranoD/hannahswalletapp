import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/backend/app_backend.dart';
import '../../providers/lock_provider.dart';

/// Puerta de la bóveda cifrada de la PWA.
///
/// Dos modos según haya bóveda o no:
///
///  * **crear**: se elige la contraseña maestra. Se pide dos veces y se avisa,
///    sin rodeos, de que no hay forma de recuperarla. Es la verdad: la clave
///    se deriva de ella y no se guarda en ninguna parte.
///  * **abrir**: contraseña o Face ID, si está activado.
class VaultGateScreen extends ConsumerStatefulWidget {
  const VaultGateScreen({required this.mode, super.key});

  final BackendStatus mode;

  @override
  ConsumerState<VaultGateScreen> createState() => _VaultGateScreenState();
}

class _VaultGateScreenState extends ConsumerState<VaultGateScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _obscure = true;
  bool _busy = false;
  bool _acknowledged = false;
  bool _biometricTried = false;
  String? _error;

  /// Cuenta atrás de la penalización por intentos fallidos.
  Duration _lockout = Duration.zero;
  Timer? _lockoutTicker;

  bool get _isCreating => widget.mode == BackendStatus.needsSetup;

  @override
  void initState() {
    super.initState();
    if (!_isCreating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshLockout();
        _tryBiometrics(automatic: true);
      });
    }
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _passphrase.dispose();
    _confirm.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Lee la penalización pendiente y arranca la cuenta atrás.
  Future<void> _refreshLockout() async {
    final Duration remaining =
        await ref.read(backendSessionProvider.notifier).lockoutRemaining();
    if (!mounted) return;

    setState(() => _lockout = remaining);
    _lockoutTicker?.cancel();
    if (remaining == Duration.zero) return;

    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() {
        _lockout = _lockout - const Duration(seconds: 1);
        if (_lockout.isNegative || _lockout == Duration.zero) {
          _lockout = Duration.zero;
          _error = null;
          t.cancel();
        }
      });
    });
  }

  /// Intenta abrir con Face ID.
  ///
  /// [automatic] distingue el intento al entrar en la pantalla del que pide el
  /// usuario tocando el botón: si el automático se cancela, no se insiste ni
  /// se enseña error, porque puede que simplemente prefiera la contraseña.
  Future<void> _tryBiometrics({bool automatic = false}) async {
    if (_busy) return;
    if (automatic && _biometricTried) return;
    if (!ref.read(vaultBiometricEnabledProvider)) return;
    _biometricTried = true;

    setState(() {
      _busy = true;
      if (!automatic) _error = null;
    });

    final UnlockOutcome outcome =
        await ref.read(backendSessionProvider.notifier).unlockWithBiometrics();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _error = switch (outcome) {
        UnlockOutcome.success || UnlockOutcome.cancelled => null,
        UnlockOutcome.unavailable => automatic
            ? null
            : 'No se pudo usar Face ID. Entra con tu contraseña.',
        _ => automatic ? null : 'No se pudo abrir con Face ID.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool biometricEnabled = ref.watch(vaultBiometricEnabledProvider);
    final bool blocked = _lockout > Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Center(child: _Logo()),
                    const SizedBox(height: 22),
                    Text(
                      _isCreating ? 'Protege tus cuentas' : AppConstants.appName,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isCreating
                          ? 'Elige una contraseña maestra. Con ella se cifra '
                              'todo lo que anotes, y sin ella nadie puede leerlo.'
                          : 'Introduce tu contraseña maestra para descifrar tus '
                              'datos.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    if (blocked)
                      _LockoutNotice(remaining: _lockout)
                    else ...<Widget>[
                      TextField(
                        controller: _passphrase,
                        focusNode: _focus,
                        autofocus: !biometricEnabled,
                        obscureText: _obscure,
                        enabled: !_busy,
                        // `newPassword` al crear y `password` al abrir: así el
                        // llavero de iOS ofrece guardarla la primera vez y
                        // autocompletarla después.
                        autofillHints: <String>[
                          _isCreating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _isCreating
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isCreating) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Contraseña maestra',
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                          ),
                        ),
                      ),
                      if (_isCreating) ...<Widget>[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirm,
                          obscureText: _obscure,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Repite la contraseña',
                            prefixIcon: Icon(Icons.key_rounded),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StrengthMeter(passphrase: _passphrase),
                        const SizedBox(height: 16),
                        _WarningBox(
                          acknowledged: _acknowledged,
                          onChanged: (bool v) =>
                              setState(() => _acknowledged = v),
                        ),
                      ],
                    ],

                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: (_busy || blocked) ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(_isCreating
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded),
                      label: Text(_isCreating ? 'Crear bóveda' : 'Desbloquear'),
                    ),

                    if (!_isCreating && biometricEnabled) ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            (_busy || blocked) ? null : _tryBiometrics,
                        icon: const Icon(Icons.face_rounded),
                        label: const Text('Usar Face ID'),
                      ),
                    ],

                    const SizedBox(height: 18),
                    Text(
                      'Todo se guarda cifrado en este dispositivo. '
                      'No hay servidor ni cuenta.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final String pass = _passphrase.text;

    if (_isCreating) {
      if (pass.length < AppConstants.minPassphraseLength) {
        setState(() => _error =
            'Usa al menos ${AppConstants.minPassphraseLength} caracteres.');
        return;
      }
      if (pass != _confirm.text) {
        setState(() => _error = 'Las dos contraseñas no coinciden.');
        return;
      }
      if (!_acknowledged) {
        setState(() => _error =
            'Confirma que entiendes que la contraseña no se puede recuperar.');
        return;
      }
    } else if (pass.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final BackendSessionNotifier session =
          ref.read(backendSessionProvider.notifier);

      if (_isCreating) {
        await session.create(passphrase: pass);
        // Al salir bien, `_AppGate` reacciona al cambio de estado y esta
        // pantalla desaparece sola; no hace falta navegar.
        return;
      }

      final UnlockOutcome outcome = await session.unlock(passphrase: pass);
      if (!mounted) return;

      switch (outcome) {
        case UnlockOutcome.success:
          return;
        case UnlockOutcome.wrongPassphrase:
          HapticFeedback.heavyImpact();
          setState(() {
            _busy = false;
            _error = 'Contraseña incorrecta.';
            _passphrase.clear();
          });
          // Tras un fallo puede haber empezado la penalización.
          await _refreshLockout();
          if (mounted && _lockout == Duration.zero) _focus.requestFocus();
        case UnlockOutcome.lockedOut:
          setState(() => _busy = false);
          await _refreshLockout();
        case UnlockOutcome.cancelled:
        case UnlockOutcome.unavailable:
          setState(() {
            _busy = false;
            _error = 'No se pudo abrir la bóveda.';
          });
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo abrir la bóveda. $error';
      });
    }
  }
}

/// Aviso de penalización con cuenta atrás.
class _LockoutNotice extends StatelessWidget {
  const _LockoutNotice({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int minutes = remaining.inMinutes;
    final int seconds = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.timer_outlined, color: AppColors.danger, size: 28),
          const SizedBox(height: 10),
          Text(
            'Demasiados intentos fallidos',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            minutes > 0
                ? 'Espera $minutes min $seconds s antes de volver a probar.'
                : 'Espera $seconds s antes de volver a probar.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
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
    );
  }
}

/// Aviso de que la contraseña es irrecuperable, con casilla de confirmación.
///
/// Es deliberadamente insistente. En una app sin servidor no hay "restablecer
/// contraseña" que valga, y descubrirlo meses después, con un año de gastos
/// dentro, sería una experiencia pésima.
class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.acknowledged, required this.onChanged});

  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded,
                  size: 20, color: AppColors.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Si olvidas esta contraseña, tus datos se pierden para '
                  'siempre. No se guarda en ningún sitio y no hay servidor '
                  'que pueda recuperarla.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          CheckboxListTile(
            value: acknowledged,
            onChanged: (bool? v) => onChanged(v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Lo entiendo', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Indicador de robustez de la contraseña.
///
/// No bloquea nada: informa. La estimación es tosca a propósito -longitud y
/// variedad de caracteres-, porque un medidor sofisticado daría una falsa
/// sensación de precisión.
class _StrengthMeter extends StatefulWidget {
  const _StrengthMeter({required this.passphrase});

  final TextEditingController passphrase;

  @override
  State<_StrengthMeter> createState() => _StrengthMeterState();
}

class _StrengthMeterState extends State<_StrengthMeter> {
  @override
  void initState() {
    super.initState();
    widget.passphrase.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.passphrase.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String value = widget.passphrase.text;
    if (value.isEmpty) return const SizedBox(height: 18);

    int score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (value.length >= 16) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;

    final (String label, Color color) = switch (score) {
      <= 2 => ('Débil', AppColors.danger),
      3 || 4 => ('Aceptable', AppColors.warning),
      _ => ('Robusta', AppColors.income),
    };

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: score / 6,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
