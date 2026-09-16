import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../data/backend/app_backend.dart';
import '../../../providers/app_settings_provider.dart';
import '../../../widgets/common.dart';

class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
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
          'hannahs-wallet-${AppDates.fileStamp(AppClock.now())}.json';

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
              '(${AppDates.shortDate(AppClock.now())})',
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
