import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/request_id.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_selectors.dart';
import '../../customers/data/customer_models.dart';
import '../../pos/application/cart.dart';
import '../../sales/data/sale_models.dart';
import '../application/payments_providers.dart';
import '../data/payment_method_models.dart';
import '../data/payment_models.dart';
import 'payment_visuals.dart';

/// "Choisir un moyen de paiement": the customer picks how they will pay the owner, sees exactly
/// where to send the money and how much, sends it from their own phone, then comes back to say so.
/// Nothing is sold and nothing is validated here — the owner verifies the payment afterwards.
class ChoosePaymentScreen extends ConsumerStatefulWidget {
  const ChoosePaymentScreen({super.key, this.customer});

  final Customer? customer;

  @override
  ConsumerState<ChoosePaymentScreen> createState() => _ChoosePaymentScreenState();
}

class _ChoosePaymentScreenState extends ConsumerState<ChoosePaymentScreen> {
  /// One key per screen and per option: choosing another option starts another payment, and
  /// choosing the same one again returns the same payment.
  final String _basketId = generateRequestId();

  String? _selectedId;
  ManualPayment? _payment;
  bool _starting = false;
  ApiException? _error;

  Future<void> _select(PaymentOption option, Cart cart) async {
    if (_starting || option.id == _selectedId) return;

    final previous = _payment;
    setState(() {
      _selectedId = option.id;
      _payment = null;
      _error = null;
      _starting = true;
    });

    // The customer changed their mind before paying: the earlier, undeclared payment is dropped.
    if (previous != null && previous.isPending) {
      unawaited(
        ref.read(paymentsApiProvider).cancel(previous.id).then((_) {}, onError: (Object _) {}),
      );
    }

    try {
      final payment = await ref
          .read(paymentsApiProvider)
          .start(
            items: [
              for (final line in cart.lines)
                CheckoutLine(productId: line.product.id, quantity: line.quantity),
            ],
            paymentMethodId: option.id,
            clientRequestId: '$_basketId-${option.id.substring(0, 8)}',
            discountTotal: cart.discount,
            customerId: widget.customer?.id,
          );
      if (!mounted || _selectedId != option.id) return;
      setState(() => _payment = payment);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _selectedId = null;
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final currency = ref.watch(currencyProvider);
    final options = ref.watch(paymentOptionsProvider);

    if (cart.isEmpty && _payment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choisir un moyen de paiement')),
        body: const EmptyState(icon: Icons.shopping_cart_outlined, message: 'Le panier est vide.'),
      );
    }

    final payment = _payment;
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un moyen de paiement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Montant à payer', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(payment?.amount ?? cart.total, currency: currency),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choisissez votre moyen de paiement',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            options.when(
              loading:
                  () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (error, _) => ErrorRetry(
                    message: errorMessage(error),
                    onRetry: () => ref.invalidate(paymentOptionsProvider),
                  ),
              data: (all) {
                final active = all.where((o) => o.isActive).toList();
                if (active.isEmpty) return const _NoOptions();
                return Column(
                  children: [
                    for (final option in active)
                      _OptionCard(
                        option: option,
                        selected: option.id == _selectedId,
                        onTap: () => _select(option, cart),
                      ),
                  ],
                );
              },
            ),
            if (_starting)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!.message, style: const TextStyle(color: AppColors.danger)),
              ),
            if (payment != null) ...[const SizedBox(height: 16), _Details(payment: payment)],
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, required this.selected, required this.onTap});

  final PaymentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: PaymentOptionLogo(
          optionId: option.id,
          provider: option.provider,
          hasLogo: option.hasLogo,
        ),
        title: Text(option.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: option.accountName == null ? null : Text(option.accountName!),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Nothing configured yet: the owner is sent to the settings, anyone else is told to ask.
class _NoOptions extends ConsumerWidget {
  const _NoOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(canManagePaymentMethodsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            const Text(
              'Aucun moyen de paiement n’est proposé pour le moment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              owner
                  ? 'Ajoutez votre numéro Orange Money, Mobile Money ou votre code marchand.'
                  : 'Demandez au propriétaire de les renseigner dans « Plus → Moyens de paiement ».',
              textAlign: TextAlign.center,
            ),
            if (owner) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/settings/payment-methods'),
                child: const Text('Configurer mes moyens de paiement'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where to send the money, how much, and how — then "J'ai effectué le paiement".
class _Details extends ConsumerWidget {
  const _Details({required this.payment});

  final ManualPayment payment;

  static String _digits(String value) => value.replaceAll(RegExp(r'[\s().-]'), '');

  Future<void> _copy(BuildContext context, WidgetRef ref, String text, String confirmation) async {
    await ref.read(clipboardWriterProvider)(text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(confirmation)));
    }
  }

  Future<void> _dial(BuildContext context, WidgetRef ref, String code) async {
    var opened = false;
    try {
      opened = await ref.read(ussdLauncherProvider)(code);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le téléphone sur cet appareil.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = payment.method;
    final toCode = PaymentProvider.sendsToCode(method.provider);
    final destination = method.destination;
    final theme = Theme.of(context);
    final ussd = method.ussdDial;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PaymentOptionLogo(
                  optionId: method.id,
                  provider: method.provider,
                  hasLogo: method.hasLogo,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(method.displayName, style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 16),
            if (method.accountName != null) ...[
              Text(toCode ? 'Marchand' : 'Titulaire', style: theme.textTheme.bodySmall),
              Text(method.accountName!, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            if (destination != null) ...[
              Text(toCode ? 'Code marchand' : 'Numéro', style: theme.textTheme.bodySmall),
              Text(
                destination,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed:
                    () => _copy(
                      context,
                      ref,
                      toCode ? destination : _digits(destination),
                      toCode ? 'Code copié' : 'Numéro copié',
                    ),
                icon: const Icon(Icons.copy_outlined),
                label: Text(toCode ? 'Copier le code' : 'Copier le numéro'),
              ),
              const SizedBox(height: 16),
            ],
            Text('Montant à envoyer', style: theme.textTheme.bodySmall),
            Text(
              formatMoney(payment.amount, currency: payment.currency),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed:
                  () => _copy(context, ref, payment.amount.round().toString(), 'Montant copié'),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copier le montant'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Envoyez exactement ce montant.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const Divider(height: 32),
            Text('Instructions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < method.instructionSteps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Expanded(child: Text(method.instructionSteps[i])),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (ussd != null) ...[
              OutlinedButton.icon(
                onPressed: () => _dial(context, ref, ussd),
                icon: const Icon(Icons.phone_outlined),
                label: const Text('Payer maintenant'),
              ),
              const SizedBox(height: 10),
            ],
            PrimaryButton(
              label: 'J’ai effectué le paiement',
              onPressed:
                  () => context.push('/pos/pay/declare/${payment.id}?till=1', extra: payment),
            ),
          ],
        ),
      ),
    );
  }
}
