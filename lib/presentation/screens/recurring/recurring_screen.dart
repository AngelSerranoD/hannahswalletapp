import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/recurring_rule_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/entities/wallet_entity.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Movimientos que se repiten solos: nómina, alquiler, suscripciones.
///
/// Se generan al abrir la app (ver `RecurringRepositoryImpl.materializeDue`),
/// recuperando también lo que se debio crear mientras estuvo cerrada.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecurringRuleEntity>> rules =
        ref.watch(recurringRulesProvider);
    final String currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: const AppTitle('Movimientos recurrentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva regla'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: switch (rules) {
        AsyncData<List<RecurringRuleEntity>>(
          :final List<RecurringRuleEntity> value
        )
            when value.isEmpty =>
          EmptyState(
            icon: Icons.autorenew_rounded,
            title: 'Sin movimientos automáticos',
            message:
                'Programa la nómina o el alquiler y se anotaran solos. Así el '
                'saldo acumulado sigue siendo fiable aunque no abras la app.',
            actionLabel: 'Crear regla',
            onAction: () => _openEditor(context),
          ),
        AsyncData<List<RecurringRuleEntity>>(
          :final List<RecurringRuleEntity> value
        ) =>
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) => _RuleCard(
              rule: value[index],
              currency: currency,
              onTap: () => _openEditor(context, existing: value[index]),
              onToggle: (bool active) => ref
                  .read(recurringRepositoryProvider)
                  .setActive(value[index].id, active),
              onDelete: () =>
                  ref.read(recurringRepositoryProvider).softDelete(value[index].id),
            ),
          ),
        AsyncError<List<RecurringRuleEntity>>(:final Object error) =>
          FailureView(message: error.toString()),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _openEditor(BuildContext context, {RecurringRuleEntity? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecurringEditorSheet(existing: existing),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.currency,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringRuleEntity rule;
  final String currency;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String every = rule.intervalCount == 1
        ? rule.frequency.label.toLowerCase()
        : 'cada ${rule.intervalCount} '
            '${switch (rule.frequency) {
            RecurrenceFrequency.daily => 'días',
            RecurrenceFrequency.weekly => 'semanas',
            RecurrenceFrequency.monthly => 'meses',
            RecurrenceFrequency.yearly => 'años',
          }}';

    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  rule.note?.trim().isNotEmpty == true
                      ? rule.note!.trim()
                      : rule.type.label,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AmountText(
                cents: rule.amountCents,
                currencyCode: currency,
                type: rule.type,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Frecuencia $every · próxima el ${AppDates.shortDate(rule.nextRunAt)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Switch.adaptive(value: rule.isActive, onChanged: onToggle),
              const SizedBox(width: 4),
              Text(
                rule.isActive ? 'Activa' : 'Pausada',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Eliminar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alta y edicion de reglas recurrentes.
class RecurringEditorSheet extends ConsumerStatefulWidget {
  const RecurringEditorSheet({this.existing, super.key});

  final RecurringRuleEntity? existing;

  @override
  ConsumerState<RecurringEditorSheet> createState() =>
      _RecurringEditorSheetState();
}

class _RecurringEditorSheetState extends ConsumerState<RecurringEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late TransactionType _type;
  late RecurrenceFrequency _frequency;
  late int _interval;
  late DateTime _nextRun;
  String? _walletId;
  String? _categoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final RecurringRuleEntity? e = widget.existing;
    _amount = TextEditingController(
      text: e == null ? '' : Money.centsToPlainString(e.amountCents),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? TransactionType.expense;
    _frequency = e?.frequency ?? RecurrenceFrequency.monthly;
    _interval = e?.intervalCount ?? 1;
    _nextRun = e?.nextRunAt ?? DateTime.now().add(const Duration(days: 1));
    _walletId = e?.walletId;
    _categoryId = e?.categoryId;
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
    final List<WalletEntity> wallets =
        ref.watch(walletsProvider).valueOrNull ?? const <WalletEntity>[];
    final List<CategoryEntity> categories =
        ref.watch(categoriesProvider(_type)).valueOrNull ??
            const <CategoryEntity>[];

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets
          .firstWhere((WalletEntity w) => w.isDefault, orElse: () => wallets.first)
          .id;
    }

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
              widget.existing == null ? 'Nueva regla' : 'Editar regla',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: const <ButtonSegment<TransactionType>>[
                ButtonSegment<TransactionType>(
                  value: TransactionType.expense,
                  label: Text('Gasto'),
                ),
                ButtonSegment<TransactionType>(
                  value: TransactionType.income,
                  label: Text('Ingreso'),
                ),
              ],
              selected: <TransactionType>{_type},
              onSelectionChanged: (Set<TransactionType> s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Importe',
                suffixText: Money.symbolFor(currency),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Concepto',
                hintText: 'Alquiler, Netflix, nómina...',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<RecurrenceFrequency>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(labelText: 'Frecuencia'),
                    items: RecurrenceFrequency.values
                        .map((RecurrenceFrequency f) =>
                            DropdownMenuItem<RecurrenceFrequency>(
                              value: f,
                              child: Text(f.label),
                            ))
                        .toList(growable: false),
                    onChanged: (RecurrenceFrequency? f) =>
                        setState(() => _frequency = f ?? _frequency),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _interval,
                    decoration: const InputDecoration(labelText: 'Cada'),
                    items: List<DropdownMenuItem<int>>.generate(
                      12,
                      (int i) => DropdownMenuItem<int>(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (int? v) => setState(() => _interval = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Próxima vez: ${AppDates.shortDate(_nextRun)}'),
            ),
            const SizedBox(height: 18),
            if (categories.isNotEmpty) ...<Widget>[
              Text('Categoría', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .map((CategoryEntity c) => ChoiceChip(
                          selected: _categoryId == c.id,
                          onSelected: (_) => setState(() => _categoryId = c.id),
                          avatar: IconBadge(
                            iconCode: c.iconCode,
                            colorValue: c.colorValue,
                            size: 22,
                          ),
                          label: Text(c.name),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
            ],
            if (wallets.isNotEmpty) ...<Widget>[
              Text('Cartera', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: wallets
                    .map((WalletEntity w) => ChoiceChip(
                          selected: _walletId == w.id,
                          onSelected: (_) => setState(() => _walletId = w.id),
                          label: Text(w.name),
                        ))
                    .toList(growable: false),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _nextRun,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) setState(() => _nextRun = picked);
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

    final DateTime now = DateTime.now();
    final String note = _note.text.trim();

    final RecurringRuleEntity rule = RecurringRuleEntity(
      id: widget.existing?.id ?? IdGenerator.newId(),
      walletId: walletId,
      categoryId: _categoryId,
      type: _type,
      amountCents: cents,
      note: note.isEmpty ? null : note,
      frequency: _frequency,
      intervalCount: _interval,
      nextRunAt: _nextRun,
      lastRunAt: widget.existing?.lastRunAt,
      isActive: widget.existing?.isActive ?? true,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      final repo = ref.read(recurringRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(rule);
      } else {
        await repo.update(rule);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }
}
