import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/i18n/cjk_font_loader.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/budget_entity.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/services/budget_planner.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../categories/category_actions.dart';
import '../categories/category_editor_sheet.dart';
import 'widgets/available_hint.dart';
import 'widgets/budget_category_picker.dart';

/// Abre el editor para crear un límite o, con [existing], para editarlo.
Future<void> openBudgetEditor(
  BuildContext context, {
  required DateTime month,
  BudgetProgress? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BudgetEditorSheet(month: month, existing: existing),
  );
}

/// Hoja para crear o editar un límite: el total del mes o uno de categorías,
/// con nombre propio opcional.
class BudgetEditorSheet extends ConsumerStatefulWidget {
  const BudgetEditorSheet({required this.month, this.existing, super.key});

  final DateTime month;
  final BudgetProgress? existing;

  @override
  ConsumerState<BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<BudgetEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _limit;
  late bool _byCategories;
  late final List<String> _selected;
  late bool _repeatEveryMonth;
  String? _error;
  bool _saving = false;

  BudgetEntity? get _existing => widget.existing?.budget;

  @override
  void initState() {
    super.initState();
    final BudgetEntity? existing = _existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _limit = TextEditingController(
      text: existing == null ? '' : Money.centsToPlainString(existing.limitCents),
    );
    _byCategories = existing != null && !existing.isGlobal;
    _selected = List<String>.of(existing?.categoryIds ?? const <String>[]);
    _repeatEveryMonth = existing?.isRecurringTemplate ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String currency = ref.watch(currencyProvider);
    final BudgetAllocation allocation = BudgetAllocation.from(
      ref.watch(budgetProgressProvider(widget.month)).valueOrNull ??
          const <BudgetProgress>[],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        // Deja sitio al teclado: sin esto el campo del importe queda tapado.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _existing == null ? 'Nuevo límite' : 'Editar límite',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _kindSelector(),
            const SizedBox(height: 16),
            _amountField(currency),
            const SizedBox(height: 10),
            // Se reconstruye con cada tecla: el objetivo es ver bajar el
            // disponible mientras se escribe, no al guardar.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _limit,
              builder: (_, TextEditingValue value, _) => AvailableHint(
                allocation: allocation,
                currency: currency,
                existing: _existing,
                forCategories: _byCategories,
                typedCents: Money.parseToCents(value.text) ?? 0,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              inputFormatters: const <TextInputFormatter>[CjkFontTrigger()],
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nombre (opcional)',
                hintText: _byCategories ? 'Ej.: Ocio del finde' : 'Ej.: Mes',
              ),
            ),
            if (_byCategories) ..._categorySection(theme),
            const SizedBox(height: 12),
            _repeatSwitch(),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Total del mes o límite de categorías. Solo al crear: convertir un límite
  /// en otro tipo al editarlo chocaría con el total que ya exista.
  Widget _kindSelector() {
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.all_inclusive_rounded),
          label: Text('Total del mes'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.folder_outlined),
          label: Text('Categorías'),
        ),
      ],
      selected: <bool>{_byCategories},
      onSelectionChanged: _existing != null
          ? null
          : (Set<bool> value) => setState(() => _byCategories = value.first),
    );
  }

  Widget _amountField(String currency) {
    return TextField(
      controller: _limit,
      autofocus: _existing == null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Límite mensual',
        prefixIcon: const Icon(Icons.euro_rounded),
        suffixText: Money.symbolFor(currency),
      ),
    );
  }

  List<Widget> _categorySection(ThemeData theme) {
    final Map<String, CategoryEntity> byId =
        ref.watch(categoriesByIdProvider).valueOrNull ??
            const <String, CategoryEntity>{};
    return <Widget>[
      const SizedBox(height: 18),
      Text('Categorías', style: theme.textTheme.titleMedium),
      const SizedBox(height: 2),
      Text(
        'Toca para añadir o quitar. Mantén pulsada para editarla o eliminarla.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      BudgetCategoryPicker(
        available: ref
                .watch(categoriesProvider(TransactionType.expense))
                .valueOrNull ??
            const <CategoryEntity>[],
        byId: byId,
        selected: _selected,
        occupiedBy: _occupiedBy(byId),
        onToggle: (String id) => setState(
          () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
        ),
        onCreate: _createCategory,
        onLongPress: (CategoryEntity c) => showCategoryActions(context, ref, c),
      ),
    ];
  }

  Widget _repeatSwitch() {
    final String month = DateRange.monthOf(widget.month)
        .label(StatsPeriod.month)
        .toLowerCase();
    return SwitchListTile.adaptive(
      value: _repeatEveryMonth,
      onChanged: (bool v) => setState(() => _repeatEveryMonth = v),
      contentPadding: EdgeInsets.zero,
      title: const Text('Repetir cada mes'),
      subtitle: Text(
        _repeatEveryMonth
            ? 'Vale para todos los meses que no tengan uno propio.'
            : 'Solo para $month.',
      ),
    );
  }

  String? get _monthKey =>
      _repeatEveryMonth ? null : DateRange.monthKeyOf(widget.month);

  /// Categorías que ya están en OTRO límite con la vigencia elegida.
  Map<String, String> _occupiedBy(Map<String, CategoryEntity> byId) {
    final List<BudgetEntity> budgets =
        ref.watch(budgetsProvider).valueOrNull ?? const <BudgetEntity>[];
    return <String, String>{
      for (final BudgetEntity b in budgets)
        if (!b.isGlobal && b.id != _existing?.id && b.monthKey == _monthKey)
          for (final String id in b.categoryIds)
            id: BudgetPlanner.nameOf(b, byId),
    };
  }

  /// Crea una categoría desde aquí mismo y la mete ya en el límite.
  Future<void> _createCategory() async {
    final String? id =
        await openCategoryEditor(context, type: TransactionType.expense);
    if (id == null || !mounted || _selected.contains(id)) return;
    setState(() => _selected.add(id));
  }

  Future<void> _save() async {
    final int? cents = Money.parseToCents(_limit.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Escribe un límite mayor que cero.');
      return;
    }
    if (_byCategories && _selected.isEmpty) {
      setState(() => _error =
          'Elige al menos una categoría, o cambia a "Total del mes".');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final DateTime now = DateTime.now();
    final BudgetEntity budget = BudgetEntity(
      id: _existing?.id ?? IdGenerator.newId(),
      name: _name.text,
      categoryIds:
          _byCategories ? List<String>.of(_selected) : const <String>[],
      monthKey: _monthKey,
      limitCents: cents,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await ref.read(budgetRepositoryProvider).save(budget);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
