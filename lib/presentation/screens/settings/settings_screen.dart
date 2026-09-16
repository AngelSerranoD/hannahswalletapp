
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../widgets/common.dart';
import 'sections/appearance_section.dart';
import 'sections/backup_section.dart';
import 'sections/danger_zone.dart';
import 'sections/management_section.dart';
import 'sections/security_section.dart';
import 'widgets/settings_group_title.dart';

/// Ajustes: apariencia, seguridad, datos y gestión.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: <Widget>[
          const SettingsGroupTitle('Apariencia'),
          const AppearanceSection(),
          const SettingsGroupTitle('Seguridad'),
          const SecuritySection(),
          const SettingsGroupTitle('Tus datos'),
          const BackupSection(),
          const SettingsGroupTitle('Gestión'),
          const ManagementSection(),
          const SettingsGroupTitle('Zona delicada'),
          const DangerZone(),
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
}
