
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../providers/app_settings_provider.dart';
import '../../../providers/lock_provider.dart';
import '../../../widgets/common.dart';

/// Seguridad en móvil: bloqueo de pantalla con biometría y PIN.
class DeviceLockSecurity extends ConsumerWidget {
  const DeviceLockSecurity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsSnapshotProvider);
    final bool hasPin = ref.watch(hasPinProvider).valueOrNull ?? false;
    final bool biometricAvailable =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.lock_outline_rounded),
            value: settings.lockEnabled,
            title: const Text('Bloquear la app'),
            subtitle: const Text(
              'El cifrado protege el fichero; esto protege la pantalla.',
            ),
            onChanged: (bool v) => _toggleLock(context, ref, v, hasPin),
          ),
          if (settings.lockEnabled) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(hasPin ? 'Cambiar PIN' : 'Establecer PIN'),
              subtitle: const Text('Se guarda derivado con PBKDF2, nunca en claro.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _setPin(context, ref),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.fingerprint_rounded),
              value: settings.biometricEnabled && biometricAvailable,
              title: const Text('Usar huella o rostro'),
              subtitle: Text(
                biometricAvailable
                    ? 'Se pedirá al abrir la app.'
                    : 'Este dispositivo no tiene biometría configurada.',
              ),
              onChanged: biometricAvailable
                  ? (bool v) => ref
                      .read(appSettingsProvider.notifier)
                      .setBiometricEnabled(v)
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: const Text('Bloquear ahora'),
              onTap: () => ref.read(appLockProvider.notifier).lockNow(),
            ),
          ],
        ],
      ),
    );
  }

  /// Activar el bloqueo exige tener credencial.
  ///
  /// Sin esta comprobacion se podría dejar la app bloqueada y sin forma de
  /// entrar: ni PIN configurado ni biometría disponible.
  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    bool value,
    bool hasPin,
  ) async {
    if (!value) {
      await ref.read(appSettingsProvider.notifier).setLockEnabled(false);
      return;
    }

    if (!hasPin) {
      final bool created = await _setPin(context, ref);
      if (!created) return;
    }
    await ref.read(appSettingsProvider.notifier).setLockEnabled(true);
  }

  Future<bool> _setPin(BuildContext context, WidgetRef ref) async {
    final String? pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (pin == null) return false;

    try {
      await ref.read(lockGateProvider).setPin(pin);
      ref.invalidate(hasPinProvider);
      if (context.mounted) showAppSnack(context, 'PIN guardado');
      return true;
    } on AppFailure catch (failure) {
      if (context.mounted) {
        showAppSnack(context, failure.message, isError: true);
      }
      return false;
    }
  }
}

/// Dialogo de alta de PIN con confirmación.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN de acceso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _first,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'PIN (4 a 8 dígitos)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _second,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Repite el PIN',
              counterText: '',
            ),
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
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final String a = _first.text.trim();
            final String b = _second.text.trim();
            if (a.length < 4) {
              setState(() => _error = 'Usa al menos 4 dígitos.');
              return;
            }
            if (a != b) {
              setState(() => _error = 'Los dos PIN no coinciden.');
              return;
            }
            Navigator.of(context).pop(a);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ Copia de datos
