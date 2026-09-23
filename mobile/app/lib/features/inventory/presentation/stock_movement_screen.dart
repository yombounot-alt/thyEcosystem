import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/json_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../products/application/products_providers.dart';
import '../../products/data/product_models.dart';
import '../application/inventory_providers.dart';
import '../data/inventory_models.dart';

enum _MovementMode { entry, exit, count }

/// "Ajuster le stock": stock in (reception), stock out (loss/breakage), or a physical count
/// (Inventaire) where the app computes the gap between theoretical and real stock.
class StockMovementScreen extends ConsumerWidget {
  const StockMovementScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ajuster le stock')),
      body: AsyncView(
        value: product,
        onRetry: () => ref.invalidate(productProvider(productId)),
        data: (p) => _MovementForm(product: p),
      ),
    );
  }
}

class _MovementForm extends ConsumerStatefulWidget {
  const _MovementForm({required this.product});

  final Product product;

  @override
  ConsumerState<_MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends ConsumerState<_MovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _note = TextEditingController();
  _MovementMode _mode = _MovementMode.entry;
  bool _saving = false;

  Product get _product => widget.product;

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _quantityLabel {
    switch (_mode) {
      case _MovementMode.entry:
        return 'Quantité reçue';
      case _MovementMode.exit:
        return 'Quantité sortie (perte, casse, usage…)';
      case _MovementMode.count:
        return 'Quantité réelle comptée';
    }
  }

  String? _validateQuantity(String? value) {
    final quantity = value == null ? null : parseUserNumber(value);
    if (quantity == null) return 'Quantité requise';
    switch (_mode) {
      case _MovementMode.entry:
        return quantity > 0 ? null : 'Doit être supérieure à 0';
      case _MovementMode.exit:
        if (quantity <= 0) return 'Doit être supérieure à 0';
        if (quantity > _product.currentStock) {
          return 'Stock insuffisant (disponible : ${formatQuantity(_product.currentStock)})';
        }
        return null;
      case _MovementMode.count:
        return quantity >= 0 ? null : 'Ne peut pas être négative';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final entered = parseUserNumber(_quantity.text)!;
    final note = _note.text.trim();
    final String type;
    final double quantity;
    String? recordedNote = note.isEmpty ? null : note;
    double? unitCost;

    switch (_mode) {
      case _MovementMode.entry:
        type = MovementType.purchaseIn;
        quantity = entered;
        unitCost = parseUserNumber(_unitCost.text);
      case _MovementMode.exit:
        type = MovementType.adjustmentOut;
        quantity = entered;
      case _MovementMode.count:
        final gap = entered - _product.currentStock;
        if (gap == 0) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Aucun écart : le stock est déjà exact.')));
          context.pop();
          return;
        }
        type = gap > 0 ? MovementType.adjustmentIn : MovementType.adjustmentOut;
        quantity = gap.abs();
        recordedNote ??= 'Inventaire (compté : ${formatQuantity(entered)})';
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryApiProvider)
          .record(
            productId: _product.id,
            type: type,
            quantity: quantity,
            unitCost: unitCost,
            note: recordedNote,
          );
      ref.invalidate(productProvider(_product.id));
      ref.invalidate(productsListProvider);
      ref.invalidate(stockMovementsProvider);
      if (!mounted) return;
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _countPreview() {
    final counted = parseUserNumber(_quantity.text);
    if (counted == null) {
      return Text(
        'Stock théorique : ${formatQuantity(_product.currentStock)} '
        '${formatUnit(_product.unit, _product.currentStock)}',
      );
    }
    final gap = counted - _product.currentStock;
    final Color color;
    if (gap == 0) {
      color = AppColors.success;
    } else if (gap > 0) {
      color = AppColors.warning;
    } else {
      color = AppColors.danger;
    }
    final gapText =
        gap == 0 ? 'aucun écart' : 'écart de ${gap > 0 ? '+' : '−'}${formatQuantity(gap.abs())}';
    return Text(
      'Stock théorique : ${formatQuantity(_product.currentStock)} '
      '${formatUnit(_product.unit, _product.currentStock)} — $gapText',
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_product.name, style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Stock actuel : ${formatQuantity(_product.currentStock)} '
                '${formatUnit(_product.unit, _product.currentStock)}',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              SegmentedButton<_MovementMode>(
                segments: const [
                  ButtonSegment(value: _MovementMode.entry, label: Text('Entrée')),
                  ButtonSegment(value: _MovementMode.exit, label: Text('Sortie')),
                  ButtonSegment(value: _MovementMode.count, label: Text('Inventaire')),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) => setState(() => _mode = selection.first),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _quantityLabel),
                validator: _validateQuantity,
                onChanged: (_) => setState(() {}),
              ),
              if (_mode == _MovementMode.count) ...[const SizedBox(height: 12), _countPreview()],
              if (_mode == _MovementMode.entry) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _unitCost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Coût unitaire (facultatif)'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final cost = parseUserNumber(v);
                    return (cost == null || cost < 0) ? 'Montant invalide' : null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (facultatif)'),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Enregistrer', onPressed: _submit, loading: _saving),
            ],
          ),
        ),
      ),
    );
  }
}
