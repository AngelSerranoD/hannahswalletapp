
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../providers/app_settings_provider.dart';
import '../../../widgets/common.dart';

/// Moneda y mascota.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsSnapshotProvider);
    return SoftCard(
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
