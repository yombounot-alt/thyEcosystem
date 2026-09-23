import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/scanning/barcode_scanner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/application/auth_selectors.dart';
import '../../categories/application/categories_providers.dart';
import '../../products/application/products_providers.dart';
import '../../products/data/product_models.dart';
import '../../products/presentation/product_photo.dart';
import '../application/cart.dart';
import 'quantity_stepper.dart';

/// "Caisse": tap products to build the cart, then go to the cart to check out.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _search = '';
  String? _categoryId;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  /// The product whose barcode or SKU is exactly [code] — null when there is none or it is ambiguous.
  /// Never a "contains": a scan must not add a product that merely looks similar.
  Product? _exactMatch(List<Product> found, String code) {
    final exact = found.where((p) => p.matchesCode(code)).toList();
    return exact.length == 1 ? exact.single : null;
  }

  /// One code read by the camera: the matching product goes straight into the cart.
  Future<ScanFeedback> _addScanned(String code) async {
    final List<Product> found;
    try {
      found = await ref.read(productsListProvider(ProductFilter(search: code)).future);
    } catch (_) {
      return const ScanFeedback.problem('Recherche impossible pour le moment.');
    }

    final product = _exactMatch(found, code);
    if (product == null) return ScanFeedback.problem('Aucun produit avec le code $code');

    final change = ref.read(cartProvider.notifier).add(product);
    if (change != CartChange.applied) {
      return ScanFeedback.problem(
        'Stock insuffisant pour ${product.name} '
        '(disponible : ${formatQuantity(product.currentStock)})',
      );
    }
    final quantity = ref.read(cartProvider).quantityOf(product.id);
    return ScanFeedback.ok('${product.name} ajouté · ${formatQuantity(quantity)} dans le panier');
  }

  /// Camera scanning: stays open so a whole basket can be scanned article after article.
  Future<void> _scanWithCamera() {
    return ref.read(barcodeScannerProvider)(
      context,
      continuous: true,
      title: 'Scanner les articles',
      onCode: _addScanned,
    );
  }

  /// Enter in the search field. Barcode readers (USB / Bluetooth "keyboard" scanners) type the
  /// code and press Enter, so an exact barcode or SKU match goes straight into the cart and the
  /// field is cleared, ready for the next scan. Anything else just runs as an ordinary search.
  Future<void> _onSearchSubmitted(String value) async {
    final code = value.trim();
    _debounce?.cancel();
    if (code.isEmpty) return;

    List<Product> found;
    try {
      found = await ref.read(productsListProvider(ProductFilter(search: code)).future);
    } catch (_) {
      // The list itself shows the error state; nothing more to do for a failed scan lookup.
      if (mounted) setState(() => _search = code);
      return;
    }
    if (!mounted) return;

    final product = _exactMatch(found, code);
    if (product != null) {
      final change = ref.read(cartProvider.notifier).add(product);
      _searchController.clear();
      setState(() => _search = '');
      _searchFocus.requestFocus();
      if (change == CartChange.applied) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${product.name} ajouté au panier'),
              duration: const Duration(milliseconds: 1200),
            ),
          );
      } else {
        showCartFeedback(context, change, product);
      }
      return;
    }

    setState(() => _search = code);
    final looksLikeCode = RegExp(r'^\d{6,}$').hasMatch(code);
    if (found.isEmpty && looksLikeCode) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Aucun produit avec le code-barres $code')));
    }
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ProductFilter(search: _search, categoryId: _categoryId);
    final products = ref.watch(productsListProvider(filter));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher ou scanner un produit',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    ref.watch(cameraScanningAvailableProvider)
                        ? IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Scanner avec la caméra',
                          onPressed: _scanWithCamera,
                        )
                        : null,
              ),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Tous'),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: _categoryId == category.id,
                        onSelected: (_) => setState(() => _categoryId = category.id),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: AsyncView(
              value: products,
              onRetry: () => ref.invalidate(productsListProvider),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message:
                        _search.isEmpty
                            ? 'Aucun produit à vendre.\nAjoutez des produits depuis l\'onglet Stock.'
                            : 'Aucun produit ne correspond à « $_search ».',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productsListProvider);
                    await ref.read(productsListProvider(filter).future);
                  },
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _PosProductTile(product: items[i]),
                  ),
                );
              },
            ),
          ),
          if (!cart.isEmpty) _CartBar(cart: cart),
        ],
      ),
    );
  }
}

class _PosProductTile extends ConsumerWidget {
  const _PosProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final quantity = ref.watch(cartProvider.select((cart) => cart.quantityOf(product.id)));
    final cart = ref.read(cartProvider.notifier);
    final soldOut = product.isOutOfStock;

    final stockText = soldOut ? 'Rupture' : 'Stock : ${formatQuantity(product.currentStock)}';

    return ListTile(
      enabled: !soldOut,
      onTap: soldOut ? null : () => showCartFeedback(context, cart.add(product), product),
      leading: ProductAvatar(product: product),
      title: Text(product.name),
      subtitle: Text('${formatMoney(product.salePrice, currency: currency)} · $stockText'),
      trailing:
          quantity > 0
              ? QuantityStepper(
                quantity: quantity,
                onDecrement: () => cart.setQuantity(product, quantity - 1),
                onIncrement: () => showCartFeedback(context, cart.add(product), product),
              )
              : Icon(
                soldOut ? Icons.block : Icons.add_circle_outline,
                color: soldOut ? AppColors.danger : AppColors.primary,
              ),
    );
  }
}

class _CartBar extends ConsumerWidget {
  const _CartBar({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final units = cart.unitCount;

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatQuantity(units)} ${units == 1 ? 'article' : 'articles'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      formatMoney(cart.subtotal, currency: currency),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.push('/pos/cart'),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Voir le panier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
