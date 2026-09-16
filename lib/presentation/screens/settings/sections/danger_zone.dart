
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../widgets/common.dart';

class DangerZone extends ConsumerWidget {
  const DangerZone({super.key});

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
