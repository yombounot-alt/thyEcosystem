import 'package:flutter/material.dart';

import '../../../core/api/json_helpers.dart';
import '../../../core/theme/formatters.dart';
import '../../sales/data/sale_models.dart';

typedef PaymentEntry = ({double amount, String method, String? note});
typedef DebtEntry = ({double amount, DateTime? dueDate, String? note});

const _paymentMethods = [
  PaymentMethod.cash,
  PaymentMethod.mobileMoney,
  PaymentMethod.card,
  PaymentMethod.other,
];

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Asks how much the customer pays back (default: everything) and how.
Future<PaymentEntry?> showRecordPaymentDialog(
  BuildContext context, {
  required double owed,
  required String currency,
}) {
  return showDialog<PaymentEntry>(
    context: context,
    builder: (_) => _RecordPaymentDialog(owed: owed, currency: currency),
  );
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.owed, required this.currency});

  final double owed;
  final String currency;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String _method = PaymentMethod.cash;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: formatQuantity(widget.owed));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseUserNumber(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Saisissez un montant supérieur à 0.');
      return;
    }
    if (amount > widget.owed) {
      setState(
        () =>
            _error =
                'Le montant dépasse la dette (${formatMoney(widget.owed, currency: widget.currency)}).',
      );
      return;
    }
    Navigator.pop(context, (amount: amount, method: _method, note: _blankToNull(_note.text)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enregistrer un paiement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dette totale : ${formatMoney(widget.owed, currency: widget.currency)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Montant reçu',
                suffixText: widget.currency,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final method in _paymentMethods)
                  ChoiceChip(
                    label: Text(PaymentMethod.label(method)),
                    selected: _method == method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (facultatif)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Adds a debt that is not tied to a sale (goods given earlier, a loan…), with an optional due date.
Future<DebtEntry?> showGrantCreditDialog(BuildContext context, {required String currency}) {
  return showDialog<DebtEntry>(
    context: context,
    builder: (_) => _GrantCreditDialog(currency: currency),
  );
}

class _GrantCreditDialog extends StatefulWidget {
  const _GrantCreditDialog({required this.currency});

  final String currency;

  @override
  State<_GrantCreditDialog> createState() => _GrantCreditDialogState();
}

class _GrantCreditDialogState extends State<_GrantCreditDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime? _dueDate;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? today.add(const Duration(days: 7)),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _submit() {
    final amount = parseUserNumber(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Saisissez un montant supérieur à 0.');
      return;
    }
    Navigator.pop(context, (amount: amount, dueDate: _dueDate, note: _blankToNull(_note.text)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une dette'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Montant dû',
                suffixText: widget.currency,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(_dueDate == null ? 'Échéance (facultatif)' : formatDay(_dueDate!)),
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: "Retirer l'échéance",
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (facultatif)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Ajouter')),
      ],
    );
  }
}
