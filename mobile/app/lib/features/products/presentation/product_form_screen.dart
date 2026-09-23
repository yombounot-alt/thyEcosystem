import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/json_helpers.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/scanning/barcode_scanner.dart';
import '../../../core/theme/formatters.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_selectors.dart';
import '../../categories/application/categories_providers.dart';
import '../application/products_providers.dart';
import '../data/product_models.dart';
import 'product_photo.dart';

/// Creates a product, or edits [productId] when given.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    if (id == null) return const _ProductForm();

    return ref
        .watch(productProvider(id))
        .when(
          data: (product) => _ProductForm(product: product),
          loading:
              () => Scaffold(
                appBar: AppBar(title: const Text('Modifier le produit')),
                body: const Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                appBar: AppBar(title: const Text('Modifier le produit')),
                body: ErrorRetry(
                  message: errorMessage(error),
                  onRetry: () => ref.invalidate(productProvider(id)),
                ),
              ),
        );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _salePrice;
  late final TextEditingController _initialStock;
  late final TextEditingController _lowStockThreshold;
  late final TextEditingController _description;
  String? _categoryId;
  bool _saving = false;

  /// A photo picked in this session; it is only sent once the product itself is saved.
  PickedPhoto? _newPhoto;

  /// The saved photo should be deleted on save ("Retirer la photo").
  bool _removePhoto = false;

  bool get _isEditing => widget.product != null;

  bool get _hasPhoto => _newPhoto != null || (widget.product?.hasImage == true && !_removePhoto);

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name);
    _sku = TextEditingController(text: p?.sku);
    _barcode = TextEditingController(text: p?.barcode);
    _purchasePrice = TextEditingController(
      text: p == null ? null : formatQuantity(p.purchasePrice),
    );
    _salePrice = TextEditingController(text: p == null ? null : formatQuantity(p.salePrice));
    _initialStock = TextEditingController();
    _lowStockThreshold = TextEditingController(
      text: p?.lowStockThreshold == null ? null : formatQuantity(p!.lowStockThreshold!),
    );
    _description = TextEditingController(text: p?.description);
    _categoryId = p?.categoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _purchasePrice.dispose();
    _salePrice.dispose();
    _initialStock.dispose();
    _lowStockThreshold.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Validates an optional numeric field: empty is fine, otherwise it must parse and satisfy [min].
  String? _optionalNumber(String? value, {double min = 0, bool strict = false}) {
    if (value == null || value.trim().isEmpty) return null;
    final number = parseUserNumber(value);
    if (number == null) return 'Nombre invalide';
    if (strict ? number <= min : number < min) {
      return strict ? 'Doit être supérieur à $min' : 'Ne peut pas être négatif';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choosePhoto() async {
    // A browser only has a file dialog (phones offer their camera there); native apps get both.
    final PhotoSource? source =
        kIsWeb
            ? PhotoSource.gallery
            : await showModalBottomSheet<PhotoSource>(
              context: context,
              builder:
                  (sheetContext) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: const Text('Prendre une photo'),
                          onTap: () => Navigator.pop(sheetContext, PhotoSource.camera),
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Choisir dans la galerie'),
                          onTap: () => Navigator.pop(sheetContext, PhotoSource.gallery),
                        ),
                      ],
                    ),
                  ),
            );
    if (source == null || !mounted) return;

    try {
      final photo = await ref.read(photoPickerProvider)(source);
      if (photo == null || !mounted) return;
      if (photo.bytes.length > maxPhotoBytes) {
        _showMessage('Photo trop lourde (2 Mo maximum).');
        return;
      }
      setState(() {
        _newPhoto = photo;
        _removePhoto = false;
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          "Impossible d'ouvrir la caméra ou la galerie. "
          "Vérifiez les autorisations de l'application.",
        );
      }
    }
  }

  /// Reads the product's barcode with the camera instead of typing its 13 digits.
  Future<void> _scanBarcode() {
    return ref.read(barcodeScannerProvider)(
      context,
      title: 'Scanner le code-barres du produit',
      onCode: (code) async {
        if (mounted) setState(() => _barcode.text = code);
        return ScanFeedback.ok('Code lu : $code');
      },
    );
  }

  /// "Retirer la photo": whatever the state, the product has no photo once saved.
  void _clearPhoto() {
    setState(() {
      _newPhoto = null;
      _removePhoto = widget.product?.hasImage == true;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final input = ProductInput(
      name: _name.text.trim(),
      salePrice: parseUserNumber(_salePrice.text)!,
      categoryId: _categoryId,
      sku: _blankToNull(_sku.text),
      barcode: _blankToNull(_barcode.text),
      purchasePrice: parseUserNumber(_purchasePrice.text),
      initialStock: parseUserNumber(_initialStock.text),
      lowStockThreshold: parseUserNumber(_lowStockThreshold.text),
      description: _blankToNull(_description.text),
    );

    setState(() => _saving = true);
    try {
      final api = ref.read(productsApiProvider);
      final existing = widget.product;
      final Product saved;
      if (existing == null) {
        saved = await api.create(input);
      } else {
        saved = await api.update(existing.id, input);
      }

      // The product is saved at this point: a failing photo must not make the user redo the form.
      String? photoProblem;
      try {
        final photo = _newPhoto;
        if (photo != null) {
          await api.uploadImage(saved.id, photo.bytes, photo.filename);
        } else if (_removePhoto) {
          await api.deleteImage(saved.id);
        }
      } on ApiException catch (e) {
        photoProblem = e.message;
      }

      ref.invalidate(productProvider(saved.id));
      ref.invalidate(productsListProvider);
      if (!mounted) return;
      if (photoProblem != null) {
        _showMessage("Produit enregistré, mais la photo n'a pas pu être envoyée : $photoProblem");
      }
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoSection() {
    const size = 120.0;
    final Widget frame;
    if (_newPhoto != null) {
      frame = PhotoFrame(bytes: _newPhoto!.bytes, width: size, height: size);
    } else if (_hasPhoto) {
      frame = ProductPhoto(product: widget.product!, width: size, height: size);
    } else {
      frame = const PhotoFrame(
        width: size,
        height: size,
        placeholder: Icon(Icons.add_a_photo_outlined, size: 36),
      );
    }

    return Column(
      children: [
        InkWell(borderRadius: BorderRadius.circular(16), onTap: _choosePhoto, child: frame),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _choosePhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_hasPhoto ? 'Changer la photo' : 'Ajouter une photo'),
            ),
            if (_hasPhoto)
              TextButton(onPressed: _clearPhoto, child: const Text('Retirer la photo')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Modifier le produit' : 'Nouveau produit')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _photoSection(),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _name,
                  label: 'Nom du produit',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 16),
                categories.when(
                  data:
                      (items) => DropdownButtonFormField<String?>(
                        initialValue: items.any((c) => c.id == _categoryId) ? _categoryId : null,
                        decoration: const InputDecoration(labelText: 'Catégorie'),
                        items: [
                          const DropdownMenuItem<String?>(child: Text('Aucune catégorie')),
                          for (final category in items)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) => setState(() => _categoryId = value),
                      ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Catégories indisponibles pour le moment.'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push('/categories'),
                    child: const Text('Gérer les catégories'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: "Prix d'achat",
                          suffixText: currency,
                        ),
                        validator: _optionalNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _salePrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Prix de vente',
                          suffixText: currency,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Prix requis';
                          return _optionalNumber(v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isEditing) ...[
                      Expanded(
                        child: TextFormField(
                          controller: _initialStock,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Stock initial'),
                          validator: _optionalNumber,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: TextFormField(
                        controller: _lowStockThreshold,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Stock minimum'),
                        validator: (v) => _optionalNumber(v, strict: true),
                      ),
                    ),
                  ],
                ),
                if (_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Le stock se modifie via « Ajuster le stock » pour garder un historique fiable.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                AppTextField(controller: _sku, label: 'SKU (facultatif)'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _barcode,
                  decoration: InputDecoration(
                    labelText: 'Code-barres (facultatif)',
                    suffixIcon:
                        ref.watch(cameraScanningAvailableProvider)
                            ? IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Scanner le code-barres',
                              onPressed: _scanBarcode,
                            )
                            : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description (facultatif)'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _isEditing ? 'Enregistrer' : 'Ajouter le produit',
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
