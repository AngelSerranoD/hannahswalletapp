
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/lock_provider.dart';
import 'device_lock_security.dart';
import 'passphrase_security.dart';

/// Seccion de seguridad, distinta en cada plataforma.
///
/// No es cosmetica: en móvil hay dos capas independientes (el fichero cifrado
/// por el sistema y el bloqueo de pantalla), mientras que en la PWA solo hay
/// una y es la contraseña maestra. Ensenar aquí un "PIN de la app" en web
/// sería prometer una proteccion que el navegador no puede dar.
class SecuritySection extends ConsumerWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool usesPassphrase = ref.watch(requiresPassphraseProvider);
    return usesPassphrase
        ? const PassphraseSecurity()
        : const DeviceLockSecurity();
  }
}
