
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../providers/app_settings_provider.dart';
import '../../widgets/common.dart';
import '../categories/categories_screen.dart';
import '../recurring/recurring_screen.dart';
import '../wallets/wallets_screen.dart';
import 'sections/backup_section.dart';
import 'sections/danger_zone.dart';
import 'sections/security_section.dart';
import 'widgets/settings_group_title.dart';

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
          const SettingsGroupTitle('Apariencia'),
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

          const SettingsGroupTitle('Seguridad'),
          const SecuritySection(),

          const SettingsGroupTitle('Tus datos'),
          const BackupSection(),

          const SettingsGroupTitle('Gestión'),
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
