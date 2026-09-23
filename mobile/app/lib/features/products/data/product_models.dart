import '../../../core/api/json_helpers.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.sku,
    required this.barcode,
    required this.unit,
    required this.purchasePrice,
    required this.salePrice,
    required this.currentStock,
    required this.lowStockThreshold,
    required this.isActive,
    required this.description,
    this.imageKey,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? sku;
  final String? barcode;
  final String unit;
  final double purchasePrice;
  final double salePrice;
  final double currentStock;
  final double? lowStockThreshold;
  final bool isActive;
  final String? description;

  /// Opaque storage key of the photo; it changes on every upload, so it doubles as a cache key.
  /// The bytes themselves come from `GET /products/:id/image`.
  final String? imageKey;

  bool get hasImage => imageKey != null;

  /// The same product with another stock level (stock net of sales still waiting to be synced).
  Product withStock(double stock) => Product(
    id: id,
    name: name,
    categoryId: categoryId,
    categoryName: categoryName,
    sku: sku,
    barcode: barcode,
    unit: unit,
    purchasePrice: purchasePrice,
    salePrice: salePrice,
    currentStock: stock,
    lowStockThreshold: lowStockThreshold,
    isActive: isActive,
    description: description,
    imageKey: imageKey,
  );

  factory Product.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String?,
      categoryName: category?['name'] as String?,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      unit: json['unit'] as String? ?? 'unite',
      purchasePrice: parseDecimal(json['purchasePrice']),
      salePrice: parseDecimal(json['salePrice']),
      currentStock: parseDecimal(json['currentStock']),
      lowStockThreshold: parseDecimalOrNull(json['lowStockThreshold']),
      isActive: json['isActive'] as bool? ?? true,
      description: json['description'] as String?,
      imageKey: json['imageKey'] as String?,
    );
  }

  double get margin => salePrice - purchasePrice;

  /// Margin as a share of the sale price; 0 when the product is free.
  double get marginPercent => salePrice == 0 ? 0 : margin / salePrice * 100;

  double get stockValue => currentStock * purchasePrice;

  bool get isOutOfStock => currentStock <= 0;

  /// Whether [code] (as typed or scanned) is exactly this product's barcode or SKU.
  /// Deliberately not a "contains": a scan must never add a product that merely looks similar.
  bool matchesCode(String code) {
    final wanted = code.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    return barcode?.toLowerCase() == wanted || sku?.toLowerCase() == wanted;
  }

  bool get isLowStock =>
      !isOutOfStock && lowStockThreshold != null && currentStock <= lowStockThreshold!;
}

/// Fields the user can set on a product. Stock only moves through inventory movements,
/// except for the initial stock given at creation.
class ProductInput {
  const ProductInput({
    required this.name,
    required this.salePrice,
    this.categoryId,
    this.sku,
    this.barcode,
    this.purchasePrice,
    this.initialStock,
    this.lowStockThreshold,
    this.description,
  });

  final String name;
  final double salePrice;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final double? purchasePrice;
  final double? initialStock;
  final double? lowStockThreshold;
  final String? description;

  /// Optional fields are omitted rather than sent as null.
  Map<String, dynamic> toCreateJson() => {
    'name': name,
    'salePrice': salePrice,
    if (categoryId != null) 'categoryId': categoryId,
    if (sku != null) 'sku': sku,
    if (barcode != null) 'barcode': barcode,
    if (purchasePrice != null) 'purchasePrice': purchasePrice,
    if (initialStock != null && initialStock! > 0) 'initialStock': initialStock,
    if (lowStockThreshold != null) 'lowStockThreshold': lowStockThreshold,
    if (description != null) 'description': description,
  };

  /// On update, cleared optional fields are sent as null so they are actually cleared.
  /// The purchase price column is not nullable, so it falls back to 0.
  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'salePrice': salePrice,
    'categoryId': categoryId,
    'sku': sku,
    'barcode': barcode,
    'purchasePrice': purchasePrice ?? 0,
    'lowStockThreshold': lowStockThreshold,
    'description': description,
  };
}
