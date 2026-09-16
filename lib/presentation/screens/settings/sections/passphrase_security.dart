
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/backend/web/biometric_unlock.dart';
import '../../../providers/app_settings_provider.dart';
import '../../../providers/lock_provider.dart';
import '../../../widgets/common.dart';

/// Seguridad de la PWA: contraseña maestra, Face ID y bloqueo automático.
class PassphraseSecurity extends ConsumerWidget {
  const PassphraseSecurity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool biometricEnabled = ref.watch(vaultBiometricEnabledProvider);
    final BiometricStatus? status =
        ref.watch(vaultBiometricStatusProvider).valueOrNull;
    final bool biometricSupported = status?.isReady ?? false;
    final int autoLock = ref.watch(settingsSnapshotProvider).autoLockMinutes;

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            isThreeLine: true,
            title: Text('Cifrado con tu contraseña'),
            subtitle: Text(
              'Tus datos se guardan cifrados con AES-256 en este navegador. '
              'La clave se deriva de tu contraseña y no se almacena.',
            ),
          ),

          // --- Face ID ---
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.face_rounded),
            value: biometricEnabled,
            isThreeLine: true,
            title: const Text('Desbloquear con Face ID'),
            // Cuando no se puede activar se dice POR QUÉ. Un interruptor gris
            // sin explicación deja al usuario sin saber si el problema es su
            // móvil, su navegador o la propia app.
            subtitle: Text(
              biometricSupported || biometricEnabled
                  ? 'Guarda una segunda copia de la clave protegida por el '
                      'Secure Enclave. Tu contraseña sigue funcionando.'
                  : (status?.message ?? 'Comprobando disponibilidad…'),
            ),
            onChanged: (biometricSupported || biometricEnabled)
                ? (bool v) => _toggleBiometrics(context, ref, v)
                : null,
          ),

          // --- Bloqueo automático ---
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Bloqueo automático'),
            subtitle: Text(
              autoLock == 0
                  ? 'Nunca. La bóveda queda abierta hasta que la cierres.'
                  : 'Tras $autoLock ${autoLock == 1 ? 'minuto' : 'minutos'} sin '
                      'usarla, y siempre al salir de la app.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickAutoLock(context, ref, autoLock),
          ),

          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('Cambiar contraseña maestra'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _changePassphrase(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Bloquear ahora'),
            subtitle: const Text('Cierra la bóveda y borra la clave de memoria.'),
            onTap: () => ref.read(backendSessionProvider.notifier).lock(),
          ),
        ],
      ),
    );
  }

  /// Activa o desactiva Face ID.
  ///
  /// Al desactivarlo se avisa de que la contraseña pasa a ser la única vía:
  /// quien haya llegado a depender de la cara para entrar puede no recordarla.
  Future<void> _toggleBiometrics(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final BackendSessionNotifier session =
        ref.read(backendSessionProvider.notifier);

    if (!enable) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Quitar Face ID'),
          content: const Text(
            'A partir de ahora solo podrás abrir la app con tu contraseña '
            'maestra. Asegúrate de recordarla.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Quitar'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      try {
        await session.disableBiometricUnlock();
        if (context.mounted) showAppSnack(context, 'Face ID desactivado.');
      } on AppFailure catch (failure) {
        if (context.mounted) {
          showAppSnack(context, failure.message, isError: true);
        }
      }
      return;
    }

    try {
      await session.enableBiometricUnlock();
      if (context.mounted) {
        showAppSnack(context, 'Ya puedes entrar con Face ID.');
      }
    } on BiometricException catch (error) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        switch (error.reason) {
          BiometricFailure.cancelled => 'Registro cancelado.',
          BiometricFailure.noPrf =>
            'Tu dispositivo permite Face ID pero no puede proteger la clave '
                'con él. Hace falta iOS 18 o posterior.',
          BiometricFailure.unsupported =>
            'Este navegador no soporta desbloqueo biométrico.',
          BiometricFailure.failed => 'No se pudo registrar Face ID.',
        },
        isError: error.reason != BiometricFailure.cancelled,
      );
    } on AppFailure catch (failure) {
      if (context.mounted) {
        showAppSnack(context, failure.message, isError: true);
      }
    }
  }

  Future<void> _pickAutoLock(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    const Map<int, String> options = <int, String>{
      1: 'Al minuto',
      3: 'A los 3 minutos',
      5: 'A los 5 minutos',
      15: 'A los 15 minutos',
      0: 'Nunca (menos seguro)',
    };

    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (int? v) => Navigator.of(ctx).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  'Al salir de la app se bloquea siempre, elijas lo que elijas.',
                  textAlign: TextAlign.center,
                ),
              ),
              ...options.entries.map(
                (MapEntry<int, String> e) => RadioListTile<int>(
                  value: e.key,
                  title: Text(e.value),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      await ref.read(appSettingsProvider.notifier).setAutoLockMinutes(picked);
    }
  }

  Future<void> _changePassphrase(BuildContext context, WidgetRef ref) async {
    final (String, String)? result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _ChangePassphraseDialog(),
    );
    if (result == null) return;

    try {
      await ref
          .read(backendSessionProvider.notifier)
          .changePassphrase(result.$1, result.$2);
      if (context.mounted) showAppSnack(context, 'Contraseña actualizada.');
    } on AppFailure catch (failure) {
      if (context.mounted) {
        showAppSnack(context, failure.message, isError: true);
      }
    }
  }
}

class _ChangePassphraseDialog extends StatefulWidget {
  const _ChangePassphraseDialog();

  @override
  State<_ChangePassphraseDialog> createState() =>
      _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends State<_ChangePassphraseDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _current,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña nueva'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la nueva'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_next.text.length < AppConstants.minPassphraseLength) {
              setState(() => _error =
                  'Usa al menos ${AppConstants.minPassphraseLength} caracteres.');
              return;
            }
            if (_next.text != _confirm.text) {
              setState(() => _error = 'Las dos contraseñas no coinciden.');
              return;
            }
            Navigator.of(context).pop((_current.text, _next.text));
          },
          child: const Text('Cambiar'),
        ),
      ],
    );
  }
}
