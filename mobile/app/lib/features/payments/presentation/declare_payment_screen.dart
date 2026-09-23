import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../pos/application/cart.dart';
import '../../products/application/products_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../application/payments_providers.dart';
import '../data/payment_models.dart';
import 'payment_visuals.dart';

/// "J'ai effectué le paiement": what the payer says they did. It is a claim — the payment then
/// waits for the owner to check that the money really arrived.
class DeclarePaymentScreen extends ConsumerWidget {
  const DeclarePaymentScreen({
    super.key,
    required this.paymentId,
    this.initial,
    this.fromTill = false,
  });

  final String paymentId;
  final ManualPayment? initial;

  /// Declared at the till: the basket is now held by the payment, so the till is emptied.
  final bool fromTill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = initial;
    if (ready != null) return _DeclareForm(payment: ready, fromTill: fromTill);

    return ref
        .watch(paymentProvider(paymentId))
        .when(
          data: (payment) => _DeclareForm(payment: payment, fromTill: fromTill),
          loading:
              () => Scaffold(
                appBar: AppBar(title: const Text('Déclarer le paiement')),
                body: const Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                appBar: AppBar(title: const Text('Déclarer le paiement')),
                body: ErrorRetry(
                  message: errorMessage(error),
                  onRetry: () => ref.invalidate(paymentProvider(paymentId)),
                ),
              ),
        );
  }
}

class _DeclareForm extends ConsumerStatefulWidget {
  const _DeclareForm({required this.payment, required this.fromTill});

  final ManualPayment payment;
  final bool fromTill;

  @override
  ConsumerState<_DeclareForm> createState() => _DeclareFormState();
}

class _DeclareFormState extends ConsumerState<_DeclareForm> {
  static final _phonePattern = RegExp(r'^\+?\d{6,15}$');
  static final _referencePattern = RegExp(r'^[A-Za-z0-9._/ -]{4,64}$');
  static const _maxProofBytes = 3 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _reference;
  late final TextEditingController _amount;
  late final TextEditingController _name;
  late DateTime _paidAt;
  PickedPhoto? _proof;
  bool _submitting = false;

  /// Set as soon as the declaration went through: the screen is on its way out (a page transition
  /// takes a moment) and a second tap must not send it again.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final previous = widget.payment.declaration; // a rejected payment is corrected, not retyped
    _phone = TextEditingController(text: previous?.payerPhone ?? '');
    _reference = TextEditingController(text: previous?.transactionReference ?? '');
    _name = TextEditingController(text: previous?.payerName ?? '');
    _amount = TextEditingController(text: widget.payment.amount.round().toString());
    _paidAt = DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_phone, _reference, _amount, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _amountSent =>
      double.tryParse(_amount.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> _pickPaidAt() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() => _paidAt = picked.isAfter(now) ? now : picked);
  }

  Future<void> _pickProof(PhotoSource source) async {
    final photo = await ref.read(photoPickerProvider)(source);
    if (photo == null || !mounted) return;
    if (photo.bytes.length > _maxProofBytes) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image trop lourde (3 Mo maximum).')));
      return;
    }
    setState(() => _proof = photo);
  }

  Future<void> _submit() async {
    if (_submitting || _done || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final payment = widget.payment;
    try {
      final api = ref.read(paymentsApiProvider);
      await api.submit(
        payment.id,
        DeclarationInput(
          payerPhone: _phone.text,
          transactionReference: _reference.text,
          amountSent: _amountSent!,
          payerName: _name.text,
          paidAt: _paidAt,
        ),
      );

      // The picture is a help for the owner: if it fails, the declaration itself stands.
      String? proofProblem;
      final proof = _proof;
      if (proof != null) {
        try {
          await api.uploadProof(payment.id, proof.bytes, proof.filename);
        } on ApiException catch (e) {
          proofProblem = e.message;
        }
      }

      _done = true;
      ref.invalidate(paymentProvider(payment.id));
      ref.invalidate(paymentsListProvider);
      ref.invalidate(paymentSummaryProvider);
      if (!mounted) return;
      if (proofProblem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paiement envoyé, mais la preuve n’a pas été envoyée : $proofProblem'),
          ),
        );
      }

      if (widget.fromTill) {
        // The basket now lives in the payment: the till is free for the next customer.
        ref.read(cartProvider.notifier).clear();
        ref.invalidate(productsListProvider);
        ref.invalidate(salesHistoryProvider);
        context.go('/payments/${payment.id}?till=1');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted && !_done) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final theme = Theme.of(context);
    final money = formatMoney(payment.amount, currency: payment.currency);

    return Scaffold(
      appBar: AppBar(title: const Text('J’ai effectué le paiement')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (payment.isRejected && payment.rejectionReason != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Refusé : ${payment.rejectionReason}. Corrigez puis renvoyez.'),
                ),
              Card(
                child: ListTile(
                  leading: PaymentOptionLogo(
                    optionId: payment.method.id,
                    provider: payment.method.provider,
                    hasLogo: payment.method.hasLogo,
                  ),
                  title: const Text('Moyen de paiement utilisé'),
                  subtitle: Text('${payment.method.displayName} · $money'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Numéro de téléphone utilisé pour payer',
                ),
                validator: (value) {
                  final compact = (value ?? '').replaceAll(RegExp(r'[\s().-]'), '');
                  if (compact.isEmpty) return 'Saisissez le numéro utilisé pour payer.';
                  return _phonePattern.hasMatch(compact)
                      ? null
                      : 'Numéro invalide (6 à 15 chiffres).';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Référence / ID de la transaction',
                  helperText: 'Dans le message de confirmation de votre opérateur.',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'La référence de transaction est obligatoire.';
                  return _referencePattern.hasMatch(text)
                      ? null
                      : 'Référence invalide (4 à 64 caractères : lettres, chiffres, . _ - /).';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Montant envoyé',
                  suffixText: payment.currency,
                ),
                validator: (value) {
                  final sent = _amountSent;
                  if (sent == null) return 'Saisissez le montant envoyé.';
                  return sent == payment.amount ? null : 'Le montant doit être exactement $money.';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom du payeur (facultatif)'),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Date et heure du paiement'),
                  subtitle: Text(formatDateTime(_paidAt)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _pickPaidAt,
                ),
              ),
              const SizedBox(height: 12),
              Text('Preuve de paiement (facultatif)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Une capture d’écran aide à la vérification, mais ne valide pas le paiement.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              if (_proof != null)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _proof!.bytes,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, _, _) => const Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => setState(() => _proof = null),
                      child: const Text('Retirer'),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickProof(PhotoSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Prendre une photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickProof(PhotoSource.gallery),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choisir une image'),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              const Text(
                'Votre paiement sera vérifié par le propriétaire avant d’être validé.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Envoyer la déclaration',
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
