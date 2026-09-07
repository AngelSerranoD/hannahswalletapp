import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/category_entity.dart';
import '../categories/categories_screen.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/entities/wallet_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Alta y edicion de movimientos.
///
/// Una sola pantalla cubre gasto, ingreso y traspaso: los tres comparten
/// importe, cartera, fecha y nota, y montar tres formularios casi identicos
/// solo multiplicaría los sitios donde corregir un fallo.
class TransactionEditorScreen extends ConsumerStatefulWidget {
  const TransactionEditorScreen({
    required this.initialType,
    this.existing,
    super.key,
  });

  final TransactionType initialType;
  final TransactionEntity? existing;

  static Future<bool?> open(
    BuildContext context, {
    required TransactionType initialType,
    TransactionEntity? existing,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TransactionEditorScreen(
          initialType: initialType,
          existing: existing,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<TransactionEditorScreen> createState() =>
      _TransactionEditorScreenState();
}

class _TransactionEditorScreenState
    extends ConsumerState<TransactionEditorScreen> {
  late TransactionType _type;
  late TextEditingController _amount;
  late TextEditingController _note;
  late DateTime _occurredAt;

  String? _categoryId;
  String? _walletId;
  String? _destinationWalletId;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final TransactionEntity? existing = widget.existing;
    _type = existing?.type ?? widget.initialType;
    _occurredAt = existing?.occurredAt ?? DateTime.now();
    _categoryId = existing?.categoryId;
    _walletId = existing?.walletId;
    _destinationWalletId = existing?.transferWalletId;
    _amount = TextEditingController(
      text: existing == null ? '' : Money.centsToPlainString(existing.amountCents),
    );
    _note = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String currency = ref.watch(currencyProvider);
    final AsyncValue<List<WalletEntity>> wallets = ref.watch(walletsProvider);
    final AsyncValue<List<CategoryEntity>> categories =
        ref.watch(categoriesProvider(_type));

    // Preseleccion de la cartera por defecto en cuanto se conocen.
    wallets.whenData((List<WalletEntity> list) {
      if (_walletId == null && list.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _walletId = list
                .firstWhere((WalletEntity w) => w.isDefault, orElse: () => list.first)
                .id);
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar movimiento' : 'Nuevo movimiento'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: <Widget>[
          _TypeSelector(
            value: _type,
            enabled: !_isEditing,
            onChanged: (TransactionType next) => setState(() {
              _type = next;
              // La categoría no se puede conservar al cambiar de tipo: las de
              // gasto no valen para un ingreso y viceversa.
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 26),
          _AmountField(controller: _amount, type: _type, currencyCode: currency),
          const SizedBox(height: 26),

          if (_type != TransactionType.transfer) ...<Widget>[
            Text('Categoría', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            categories.when(
              data: (List<CategoryEntity> list) => _CategoryPicker(
                type: _type,
                categories: list,
                selectedId: _categoryId,
                onSelected: (String id) => setState(
                  () => _categoryId = _categoryId == id ? null : id,
                ),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (Object e, _) => FailureView(message: e.toString()),
            ),
            const SizedBox(height: 26),
          ],

          Text(
            _type == TransactionType.transfer ? 'Desde' : 'Cartera',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          wallets.when(
            data: (List<WalletEntity> list) => _WalletPicker(
              wallets: list,
              selectedId: _walletId,
              onSelected: (String id) => setState(() {
                _walletId = id;
                if (_destinationWalletId == id) _destinationWalletId = null;
              }),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (Object e, _) => FailureView(message: e.toString()),
          ),

          if (_type == TransactionType.transfer) ...<Widget>[
            const SizedBox(height: 22),
            Text('Hacia', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            wallets.when(
              data: (List<WalletEntity> list) => _WalletPicker(
                wallets: list
                    .where((WalletEntity w) => w.id != _walletId)
                    .toList(growable: false),
                selectedId: _destinationWalletId,
                onSelected: (String id) =>
                    setState(() => _destinationWalletId = id),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (Object e, _) => FailureView(message: e.toString()),
            ),
          ],

          const SizedBox(height: 26),
          _DateRow(
            value: _occurredAt,
            onChanged: (DateTime next) => setState(() => _occurredAt = next),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Cafe con Marta, gasolina, alquiler...',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            maxLength: 120,
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: switch (_type) {
              TransactionType.income => AppColors.income,
              TransactionType.expense => AppColors.primary,
              TransactionType.transfer => theme.colorScheme.secondary,
            },
            foregroundColor: Colors.white,
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_isEditing ? 'Guardar cambios' : 'Guardar'),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final int? cents = Money.parseToCents(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Escribe un importe mayor que cero.');
      return;
    }
    final String? walletId = _walletId;
    if (walletId == null) {
      setState(() => _error = 'Elige una cartera.');
      return;
    }
    if (_type == TransactionType.transfer && _destinationWalletId == null) {
      setState(() => _error = 'Elige la cartera de destino.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final DateTime now = DateTime.now();
    final String note = _note.text.trim();

    final TransactionEntity entity = TransactionEntity(
      id: widget.existing?.id ?? IdGenerator.newId(),
      walletId: walletId,
      categoryId: _type == TransactionType.transfer ? null : _categoryId,
      type: _type,
      amountCents: cents,
      note: note.isEmpty ? null : note,
      occurredAt: _occurredAt,
      transferWalletId:
          _type == TransactionType.transfer ? _destinationWalletId : null,
      recurringRuleId: widget.existing?.recurringRuleId,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      final repo = ref.read(transactionRepositoryProvider);
      if (_isEditing) {
        await repo.update(entity);
      } else {
        await repo.create(entity);
      }

      if (!mounted) return;

      // Aquí esta el enlace con la mascota que pedia el Modulo 5: un gasto
      // guardado con exito dispara la celebracion del gato. Va DESPUES del
      // await para que solo celebre lo que de verdad se ha grabado.
      if (!_isEditing) {
        ref.read(kittyControllerProvider).fireSuccess();
      }

      Navigator.of(context).pop(true);
      showAppSnack(
        context,
        _isEditing ? 'Movimiento actualizado' : 'Movimiento guardado',
      );
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. $error';
      });
    }
  }
}

/// Selector de gasto / ingreso / traspaso.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  /// Al editar no se deja cambiar el tipo: convertir un gasto en traspaso
  /// implicaria inventarse una cartera de destino y recalcular dos saldos.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TransactionType>(
      segments: const <ButtonSegment<TransactionType>>[
        ButtonSegment<TransactionType>(
          value: TransactionType.expense,
          label: Text('Gasto'),
          icon: Icon(Icons.north_east_rounded, size: 17),
        ),
        ButtonSegment<TransactionType>(
          value: TransactionType.income,
          label: Text('Ingreso'),
          icon: Icon(Icons.south_west_rounded, size: 17),
        ),
        ButtonSegment<TransactionType>(
          value: TransactionType.transfer,
          label: Text('Traspaso'),
          icon: Icon(Icons.swap_horiz_rounded, size: 17),
        ),
      ],
      selected: <TransactionType>{value},
      onSelectionChanged: enabled
          ? (Set<TransactionType> s) => onChanged(s.first)
          : null,
      showSelectedIcon: false,
    );
  }
}

/// Campo del importe, grande y centrado.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.type,
    required this.currencyCode,
  });

  final TextEditingController controller;
  final TransactionType type;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = switch (type) {
      TransactionType.income => AppColors.income,
      TransactionType.expense => AppColors.primary,
      TransactionType.transfer => theme.colorScheme.secondary,
    };

    return Column(
      children: <Widget>[
        Text('Importe', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          autofocus: controller.text.isEmpty,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // Se admiten coma y punto: el teclado numerico de Android muestra
          // coma en espanol y punto en otras configuraciones, y obligar al
          // usuario a acertar con el separador es una fuente de frustracion
          // absurda. `Money.parseToCents` normaliza después.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(12),
          ],
          style: theme.textTheme.displaySmall?.copyWith(
            color: color,
            fontSize: 46,
          ),
          decoration: InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: '0,00',
            hintStyle: theme.textTheme.displaySmall?.copyWith(
              fontSize: 46,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            suffixText: Money.symbolFor(currencyCode),
            suffixStyle: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
        ),
        Container(height: 2, width: 120, color: color.withValues(alpha: 0.35)),
      ],
    );
  }
}

/// Rejilla de categorías, con alta al vuelo.
///
/// El chip "Nueva" del final es lo que evita el callejón sin salida de estar
/// anotando un gasto y descubrir que falta la categoría: obligaba a descartar
/// el movimiento, ir a Ajustes, crearla y empezar de nuevo. Ahora se crea aquí
/// mismo y queda seleccionada.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.type,
  });

  final List<CategoryEntity> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final TransactionType type;

  /// Abre el editor de categorías y selecciona la que se cree.
  Future<void> _createCategory(BuildContext context) async {
    final String? createdId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(type: type),
    );
    if (createdId != null) onSelected(createdId);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        ...categories.map((CategoryEntity c) {
        final bool selected = c.id == selectedId;
        final Color color = Color(c.colorValue);
        return InkWell(
          onTap: () => onSelected(c.id),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.20)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconBadge(
                  iconCode: c.iconCode,
                  colorValue: c.colorValue,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(c.name, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        );
      }),

        // Chip de alta rápida, siempre el último.
        InkWell(
          onTap: () => _createCategory(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              border: Border.all(color: theme.colorScheme.outline, width: 1.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28 * 0.34),
                  ),
                  child: Icon(Icons.add_rounded,
                      size: 16, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(width: 8),
                Text('Nueva', style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Chips de cartera.
class _WalletPicker extends StatelessWidget {
  const _WalletPicker({
    required this.wallets,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WalletEntity> wallets;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (wallets.isEmpty) {
      return Text(
        'No hay carteras disponibles.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: wallets.map((WalletEntity w) {
        return ChoiceChip(
          selected: w.id == selectedId,
          onSelected: (_) => onSelected(w.id),
          avatar: IconBadge(
            iconCode: w.iconCode,
            colorValue: w.colorValue,
            size: 24,
          ),
          label: Text(w.name),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Fecha y hora del movimiento.
class _DateRow extends StatelessWidget {
  const _DateRow({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(context),
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(AppDates.shortDate(value)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickTime(context),
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(AppDates.time(value)),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2000),
      // Se permite anotar en el futuro: es normal registrar un recibo
      // domiciliado con la fecha en que se cargara.
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('es', 'ES'),
    );
    if (picked == null) return;
    onChanged(DateTime(
      picked.year,
      picked.month,
      picked.day,
      value.hour,
      value.minute,
    ));
  }

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (picked == null) return;
    onChanged(DateTime(
      value.year,
      value.month,
      value.day,
      picked.hour,
      picked.minute,
    ));
  }
}
