import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/json_helpers.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_selectors.dart';
import '../application/expenses_providers.dart';
import '../data/expense_models.dart';

/// Records an expense, or edits [expenseId] when given.
class ExpenseFormScreen extends ConsumerWidget {
  const ExpenseFormScreen({super.key, this.expenseId});

  final String? expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = expenseId;
    if (id == null) return const _ExpenseForm();

    return ref
        .watch(expenseProvider(id))
        .when(
          data: (expense) => _ExpenseForm(expense: expense),
          loading:
              () => Scaffold(
                appBar: AppBar(title: const Text('Modifier la dépense')),
                body: const Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                appBar: AppBar(title: const Text('Modifier la dépense')),
                body: ErrorRetry(
                  message: errorMessage(error),
                  onRetry: () => ref.invalidate(expenseProvider(id)),
                ),
              ),
        );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({this.expense});

  final Expense? expense;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late String _category;
  late DateTime _date;
  bool _saving = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    final now = DateTime.now();
    _amount = TextEditingController(text: e == null ? null : formatQuantity(e.amount));
    _description = TextEditingController(text: e?.description);
    _category = e?.category ?? ExpenseCategory.codes.first;
    _date = e?.expenseDate ?? DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final description = _description.text.trim();
    final input = ExpenseInput(
      category: _category,
      amount: parseUserNumber(_amount.text)!,
      expenseDate: _date,
      description: description.isEmpty ? null : description,
    );

    setState(() => _saving = true);
    try {
      final api = ref.read(expensesApiProvider);
      final existing = widget.expense;
      if (existing == null) {
        await api.create(input);
      } else {
        await api.update(existing.id, input);
      }
      invalidateExpenseData(ref, expenseId: existing?.id);
      if (!mounted) return;
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Modifier la dépense' : 'Nouvelle dépense')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: [
                    for (final code in ExpenseCategory.codes)
                      DropdownMenuItem(value: code, child: Text(ExpenseCategory.label(code))),
                  ],
                  onChanged: (value) => setState(() => _category = value ?? _category),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Montant', suffixText: currency),
                  validator: (v) {
                    final amount = v == null ? null : parseUserNumber(v);
                    if (amount == null) return 'Montant requis';
                    return amount > 0 ? null : 'Doit être supérieur à 0';
                  },
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text('Date : ${formatDay(_date)}'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (facultatif)'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _isEditing ? 'Enregistrer' : 'Ajouter la dépense',
                  onPressed: _submit,
                  loading: _saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
