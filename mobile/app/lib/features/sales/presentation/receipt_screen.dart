import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sharing/file_sharer.dart';
import '../../../core/sharing/text_sharer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../business/application/business_providers.dart';
import '../../business/data/business_api.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/application/products_providers.dart';
import '../application/receipt_pdf.dart';
import '../application/receipt_text.dart';
import '../application/sales_providers.dart';
import '../data/sale_models.dart';

/// Who the receipt is from. Address/phone come from a second request; the receipt must not wait
/// on (or fail with) it, so the business of the session is the fallback.
BusinessDetails receiptBusiness(WidgetRef ref) {
  final business = ref.watch(businessDetailsProvider);
  final active = ref.watch(activeBusinessProvider);
  return business.value ??
      BusinessDetails(
        id: active?.id ?? '',
        name: active?.name ?? 'THY Business',
        currency: active?.currency ?? 'GNF',
      );
}

/// Receipt of one sale. [change] is only known right after checkout (cash given back).
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.saleId, this.change = 0});

  final String saleId;
  final double change;

  Future<void> _voidSale(BuildContext context, WidgetRef ref, Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Annuler la vente ${sale.saleNumber} ?'),
            content: const Text(
              'Le stock sera restitué et la dette éventuelle du client sera annulée. '
              'Cette action est définitive.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Garder la vente'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Annuler la vente'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(salesApiProvider).voidSale(sale.id);
      ref.invalidate(saleProvider(sale.id));
      ref.invalidate(salesHistoryProvider);
      ref.invalidate(productsListProvider);
      ref.invalidate(stockMovementsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleProvider(saleId));
    final details = receiptBusiness(ref);

    final loaded = sale.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu'),
        leading:
            context.canPop()
                ? null
                : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Fermer',
                  onPressed: () => context.go('/pos'),
                ),
        actions: [
          if (loaded != null) ReceiptPdfButton(sale: loaded, business: details, change: change),
          if (loaded != null && !loaded.isVoid)
            PopupMenuButton<String>(
              onSelected: (_) => _voidSale(context, ref, loaded),
              itemBuilder:
                  (_) => const [PopupMenuItem(value: 'void', child: Text('Annuler la vente'))],
            ),
        ],
      ),
      body: AsyncView(
        value: sale,
        onRetry: () => ref.invalidate(saleProvider(saleId)),
        data:
            (s) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ReceiptCard(sale: s, business: details, change: change),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            () => ref.read(textSharerProvider)(
                              buildReceiptText(s, details, change: change),
                            ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Partager'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.go('/pos'),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Nouvelle vente'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      ),
    );
  }
}

/// "Reçu en PDF": builds the receipt as a PDF and opens the share sheet with it.
class ReceiptPdfButton extends ConsumerStatefulWidget {
  const ReceiptPdfButton({
    super.key,
    required this.sale,
    required this.business,
    required this.change,
  });

  final Sale sale;
  final BusinessDetails business;
  final double change;

  @override
  ConsumerState<ReceiptPdfButton> createState() => ReceiptPdfButtonState();
}

class ReceiptPdfButtonState extends ConsumerState<ReceiptPdfButton> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final fonts = await ref.read(receiptFontsProvider.future);
      final bytes = await buildReceiptPdf(
        widget.sale,
        widget.business,
        fonts: fonts,
        change: widget.change,
      );
      await ref.read(fileSharerProvider)(
        bytes: bytes,
        filename: receiptPdfFilename(widget.sale),
        mimeType: 'application/pdf',
        text: 'Reçu ${widget.sale.saleNumber} — ${widget.business.name}',
      );
    } catch (error, stack) {
      debugPrint('Receipt PDF failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de créer le PDF du reçu. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon:
          _busy
              ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.picture_as_pdf_outlined),
      tooltip: 'Reçu en PDF',
      onPressed: _busy ? null : _share,
    );
  }
}

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.sale, required this.business, required this.change});

  final Sale sale;
  final BusinessDetails business;
  final double change;

  @override
  Widget build(BuildContext context) {
    final currency = business.currency;
    final textTheme = Theme.of(context).textTheme;
    final address = business.address;
    final phone = business.phone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.storefront, size: 40, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(business.name, textAlign: TextAlign.center, style: textTheme.titleLarge),
            if (address != null && address.isNotEmpty)
              Text(address, textAlign: TextAlign.center, style: textTheme.bodySmall),
            if (phone != null && phone.isNotEmpty)
              Text(phone, textAlign: TextAlign.center, style: textTheme.bodySmall),
            const Divider(height: 32),
            _Line('Reçu', sale.saleNumber, bold: true),
            _Line('Date', formatDateTime(sale.soldAt)),
            if (sale.customer != null) _Line('Client', sale.customer!.fullName),
            if (sale.isVoid)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                color: AppColors.danger.withValues(alpha: 0.1),
                child: const Text(
                  'VENTE ANNULÉE',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
                ),
              ),
            const Divider(height: 32),
            for (final item in sale.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName),
                          Text(
                            '${formatQuantity(item.quantity)} × '
                            '${formatMoney(item.unitPrice, currency: currency)}',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(formatMoney(item.lineTotal, currency: currency)),
                  ],
                ),
              ),
            const Divider(height: 24),
            _Line('Sous-total', formatMoney(sale.subtotal, currency: currency)),
            if (sale.discountTotal > 0)
              _Line('Réduction', '−${formatMoney(sale.discountTotal, currency: currency)}'),
            _Line('TOTAL', formatMoney(sale.total, currency: currency), bold: true, large: true),
            const SizedBox(height: 8),
            for (final payment in sale.payments)
              _Line(
                PaymentMethod.label(payment.method),
                formatMoney(payment.amount, currency: currency),
              ),
            if (change > 0)
              _Line(
                'Monnaie rendue',
                formatMoney(change, currency: currency),
                color: AppColors.success,
              ),
            if (sale.isOnCredit && !sale.isVoid)
              _Line(
                'Reste à payer',
                formatMoney(sale.amountDue, currency: currency),
                color: AppColors.danger,
                bold: true,
              ),
            const SizedBox(height: 16),
            Text(
              'Merci de votre confiance !',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false, this.large = false, this.color});

  final String label;
  final String value;
  final bool bold;
  final bool large;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: large ? 20 : 15,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
