import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_catalog.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/wallet_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Carteras (efectivo, banco, tarjeta...) con su saldo calculado.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WalletWithBalance>> wallets =
        ref.watch(walletsWithBalanceProvider);
    final String currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const AppTitle('Carteras')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva cartera'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: switch (wallets) {
        AsyncData<List<WalletWithBalance>>(:final List<WalletWithBalance> value) =>
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final WalletWithBalance item = value[index];
              return SoftCard(
                onTap: () => _openEditor(context, existing: item.wallet),
                child: Row(
                  children: <Widget>[
                    IconBadge(
                      iconCode: item.wallet.iconCode,
                      colorValue: item.wallet.colorValue,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  item.wallet.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.wallet.isDefault) ...<Widget>[
                                const SizedBox(width: 8),
                                const _DefaultTag(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saldo actual',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    AmountText(
                      cents: item.balanceCents,
                      currencyCode: currency,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              );
            },
          ),
        AsyncError<List<WalletWithBalance>>(:final Object error) =>
          FailureView(message: error.toString()),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _openEditor(BuildContext context, {WalletEntity? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WalletEditorSheet(existing: existing),
    );
  }
}

class _DefaultTag extends StatelessWidget {
  const _DefaultTag();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Por defecto',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Alta y edicion de carteras.
class WalletEditorSheet extends ConsumerStatefulWidget {
  const WalletEditorSheet({this.existing, super.key});

  final WalletEntity? existing;

  @override
  ConsumerState<WalletEditorSheet> createState() => _WalletEditorSheetState();
}

class _WalletEditorSheetState extends ConsumerState<WalletEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _initial;
  late int _iconCode;
  late int _colorValue;
  late bool _isDefault;
  String? _error;

  @override
  void initState() {
    super.initState();
    final WalletEntity? e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _initial = TextEditingController(
      text: e == null ? '' : Money.centsToPlainString(e.initialBalanceCents),
    );
    _iconCode = e?.iconCode ?? IconCatalog.walletIcons.first.codePoint;
    _colorValue = e?.colorValue ?? AppColors.categoryPalette.first;
    _isDefault = e?.isDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String currency = ref.watch(currencyProvider);
    final bool isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isEditing ? 'Editar cartera' : 'Nueva cartera',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Cuenta corriente, efectivo, hucha...',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _initial,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Saldo inicial',
                helperText: 'Lo que ya tenias antes de usar la app.',
                suffixText: Money.symbolFor(currency),
              ),
            ),
            const SizedBox(height: 20),
            Text('Icono', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _IconGrid(
              icons: IconCatalog.walletIcons,
              selected: _iconCode,
              color: Color(_colorValue),
              onSelected: (int code) => setState(() => _iconCode = code),
            ),
            const SizedBox(height: 20),
            Text('Color', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _ColorGrid(
              selected: _colorValue,
              onSelected: (int value) => setState(() => _colorValue = value),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: _isDefault,
              onChanged: (bool v) => setState(() => _isDefault = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Cartera por defecto'),
              subtitle: const Text('Se preselecciona al anotar un movimiento.'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
            if (isEditing) ...<Widget>[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _archive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archivar cartera'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre a la cartera.');
      return;
    }

    final DateTime now = DateTime.now();
    final WalletEntity wallet = WalletEntity(
      id: widget.existing?.id ?? IdGenerator.newId(),
      name: name,
      iconCode: _iconCode,
      colorValue: _colorValue,
      currencyCode: ref.read(currencyProvider),
      initialBalanceCents: Money.parseToCents(_initial.text) ?? 0,
      isDefault: _isDefault,
      isArchived: widget.existing?.isArchived ?? false,
      sortOrder: widget.existing?.sortOrder ?? 0,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      final repo = ref.read(walletRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(wallet);
      } else {
        await repo.update(wallet);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }

  Future<void> _archive() async {
    final WalletEntity? existing = widget.existing;
    if (existing == null) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Archivar cartera'),
        content: const Text(
          'Dejara de aparecer y su saldo no contara en el total, pero sus '
          'movimientos se conservan intactos.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(walletRepositoryProvider).archive(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }
}

/// Rejilla de iconos seleccionables.
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.icons,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final List<IconData> icons;
  final int selected;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: icons.map((IconData icon) {
        final bool isSelected = icon.codePoint == selected;
        return InkWell(
          onTap: () => onSelected(icon.codePoint),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.18)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected ? color : scheme.onSurfaceVariant,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Rejilla de colores de la paleta de la app.
class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppColors.categoryPalette.map((int value) {
        final bool isSelected = value == selected;
        return InkWell(
          onTap: () => onSelected(value),
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(value),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2.4,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Reutilizables desde la pantalla de categorías.
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    required this.icons,
    required this.selected,
    required this.color,
    required this.onSelected,
    super.key,
  });

  final List<IconData> icons;
  final int selected;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => _IconGrid(
        icons: icons,
        selected: selected,
        color: color,
        onSelected: onSelected,
      );
}

class ColorPickerGrid extends StatelessWidget {
  const ColorPickerGrid({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) =>
      _ColorGrid(selected: selected, onSelected: onSelected);
}
