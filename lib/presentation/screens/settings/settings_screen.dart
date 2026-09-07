import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../../../data/backend/app_backend.dart';
import '../../../data/backend/web/biometric_unlock.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/lock_provider.dart';
import '../../widgets/common.dart';
import '../categories/categories_screen.dart';
import '../recurring/recurring_screen.dart';
import '../wallets/wallets_screen.dart';

/// Ajustes: apariencia, seguridad, datos y gestion.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const AppTitle('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: <Widget>[
          const _GroupTitle('Apariencia'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.euro_rounded),
                  title: const Text('Moneda'),
                  subtitle: Text(
                    '${settings.currencyCode} · '
                    '${Money.symbolFor(settings.currencyCode)}',
                  ),
                  onTap: () => _pickCurrency(context, ref, settings.currencyCode),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.pets_rounded),
                  value: settings.mascotEnabled,
                  onChanged: (bool v) =>
                      ref.read(appSettingsProvider.notifier).setMascotEnabled(v),
                  title: const Text('Mostrar la mascota'),
                  subtitle: const Text('El gato reacciona a tu presupuesto.'),
                ),
              ],
            ),
          ),

          const _GroupTitle('Seguridad'),
          const _SecuritySection(),

          const _GroupTitle('Tus datos'),
          const _BackupSection(),

          const _GroupTitle('Gestión'),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Carteras'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WalletsScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categorías'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CategoriesScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.autorenew_rounded),
                  title: const Text('Movimientos recurrentes'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecurringScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const _GroupTitle('Zona delicada'),
          const _DangerZone(),

          const SizedBox(height: 28),
          Center(
            child: Text(
              '${AppConstants.appName} · 100 % offline\n'
              'Cifrado local: ${ref.watch(appBackendProvider).displayName}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (String? v) => Navigator.of(ctx).pop(v),
          child: ListView(
            shrinkWrap: true,
            children: Money.supportedCurrencies
                .map((({String code, String label}) c) => RadioListTile<String>(
                      value: c.code,
                      title: Text(c.label),
                      secondary: Text(
                        Money.symbolFor(c.code),
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ))
                .toList(growable: false),
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(appSettingsProvider.notifier).setCurrency(picked);
    }
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 24, 6, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}

// ------------------------------------------------------------- Seguridad

/// Seccion de seguridad, distinta en cada plataforma.
///
/// No es cosmetica: en móvil hay dos capas independientes (el fichero cifrado
/// por el sistema y el bloqueo de pantalla), mientras que en la PWA solo hay
/// una y es la contraseña maestra. Ensenar aquí un "PIN de la app" en web
/// sería prometer una proteccion que el navegador no puede dar.
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool usesPassphrase = ref.watch(requiresPassphraseProvider);
    return usesPassphrase
        ? const _PassphraseSecurity()
        : const _DeviceLockSecurity();
  }
}

/// Seguridad de la PWA: contraseña maestra, Face ID y bloqueo automático.
class _PassphraseSecurity extends ConsumerWidget {
  const _PassphraseSecurity();

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

/// Seguridad en móvil: bloqueo de pantalla con biometría y PIN.
class _DeviceLockSecurity extends ConsumerWidget {
  const _DeviceLockSecurity();

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

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('Exportar copia (JSON)'),
            subtitle: const Text(
              'Todo tu historial en un fichero que puedes guardar donde quieras.',
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Importar copia'),
            subtitle: const Text('Restaura o fusiona desde un fichero JSON.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _import,
          ),
        ],
      ),
    );
  }

  /// Exporta y abre el panel de compartir.
  ///
  /// Antes se avisa de que el JSON sale SIN cifrar: dentro de la app los datos
  /// viven protegidos, pero el fichero que se comparte es legible por
  /// cualquiera. Callarselo sería vender una privacidad que el fichero no da.
  Future<void> _export() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Exportar tus datos'),
        content: const Text(
          'El fichero JSON no va cifrado: cualquiera que lo abra vera tus '
          'movimientos. Guardalo en un sitio de confianza.\n\n'
          'Es también tu único seguro si olvidas la contraseña maestra.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Entendido, exportar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final String json = await ref.read(backupProvider).exportToJsonString();
      final String name =
          'hannahs-wallet-${AppDates.fileStamp(DateTime.now())}.json';

      if (!mounted) return;

      // `XFile.fromData` construye el fichero EN MEMORIA. Es lo que permite
      // que este mismo código sirva en móvil y en la PWA: en el navegador no
      // hay directorio temporal donde escribir, y `share_plus` se encarga de
      // ofrecer la hoja de compartir de iOS o la descarga, según el caso.
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              Uint8List.fromList(utf8.encode(json)),
              name: name,
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: <String>[name],
          subject: 'Copia de ${AppConstants.appName} '
              '(${AppDates.shortDate(DateTime.now())})',
          text: 'Copia de seguridad de ${AppConstants.appName}.',
        ),
      );
      if (mounted) showAppSnack(context, 'Copia generada.');
    } on AppFailure catch (failure) {
      if (mounted) showAppSnack(context, failure.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Importa tras ensenar un resumen del contenido del fichero.
  Future<void> _import() async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Elige la copia de seguridad',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (file == null) return;

    final String source;
    try {
      // Se lee por bytes y no por ruta: en web y en algunos proveedores de
      // Android (Drive, Descargas) no hay un fichero real en disco al que
      // apuntar, solo un flujo del sistema.
      final Uint8List bytes = await file.readAsBytes();
      source = utf8.decode(bytes);
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'No se pudo leer el fichero. $error', isError: true);
      }
      return;
    }

    final BackupPort service = ref.read(backupProvider);

    final BackupSummary preview;
    try {
      preview = await service.inspect(source);
    } on AppFailure catch (failure) {
      if (mounted) showAppSnack(context, failure.message, isError: true);
      return;
    }
    if (!mounted) return;

    final bool? replace = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _ImportDialog(preview: preview),
    );
    if (replace == null) return;

    setState(() => _busy = true);
    try {
      final BackupImportResult report =
          await service.importFromJson(source, replaceExisting: replace);
      ref.read(dataRevisionProvider.notifier).bump();
      ref.invalidate(appSettingsProvider);
      if (!mounted) return;
      showAppSnack(
        context,
        'Restaurados ${report.totalInserted} registros'
        '${report.totalSkipped > 0 ? ' (${report.totalSkipped} descartados)' : ''}.',
      );
    } on AppFailure catch (failure) {
      if (mounted) showAppSnack(context, failure.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Resumen del backup y eleccion de estrategia.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.preview});

  final BackupSummary preview;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _replace = true;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BackupSummary p = widget.preview;

    return AlertDialog(
      title: const Text('Restaurar copia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (p.exportedAt != null)
              Text(
                'Creada el ${AppDates.shortDate(p.exportedAt!.toLocal())}',
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 10),
            Text('Contiene:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '· ${p.transactionCount} movimientos\n'
              '· ${p.categoryCount} categorías\n'
              '· ${p.walletCount} carteras\n'
              '· ${p.budgetCount} presupuestos',
              style: theme.textTheme.bodyMedium,
            ),
            if (!p.checksumOk) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Aviso: la huella del fichero no cuadra. Puede que se haya '
                'editado a mano. Se puede restaurar igualmente.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning),
              ),
            ],
            const SizedBox(height: 14),
            RadioGroup<bool>(
              groupValue: _replace,
              onChanged: (bool? v) => setState(() => _replace = v ?? true),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<bool>(
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reemplazar todo'),
                    subtitle: Text(
                      'Borra lo actual y deja solo la copia.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fusionar'),
                    subtitle: Text(
                      'Añade lo que falte y actualiza lo que coincida.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_replace),
          child: const Text('Restaurar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- Zona delicada

class _DangerZone extends ConsumerWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Vaciar la papelera'),
            subtitle: const Text(
              'Elimina definitivamente los movimientos borrados hace mas de 30 días.',
            ),
            onTap: () async {
              final int removed = await ref
                  .read(transactionRepositoryProvider)
                  .purgeDeleted();
              if (context.mounted) {
                showAppSnack(context, 'Eliminados $removed registros.');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            title: const Text(
              'Borrar todos mis datos',
              style: TextStyle(color: AppColors.danger),
            ),
            subtitle: const Text('Irreversible. Exporta una copia antes.'),
            onTap: () => _wipe(context, ref),
          ),
        ],
      ),
    );
  }

  /// Borrado total con confirmación escrita.
  ///
  /// Se pide teclear una palabra en vez de un simple "Aceptar": esto destruye
  /// también el material criptográfico, así que después no hay ninguna copia
  /// del sistema capaz de recuperar nada.
  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Borrar todo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Se borrarán los datos cifrados y su clave. No hay forma de '
              'recuperarlo después.\n\nEscribe BORRAR para confirmar.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'BORRAR'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(
              controller.text.trim().toUpperCase() == 'BORRAR',
            ),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (ok != true) return;

    await ref.read(backendSessionProvider.notifier).wipe();
    if (!context.mounted) return;

    showAppSnack(context, 'Datos borrados. La app volverá a empezar de cero.');
  }
}
