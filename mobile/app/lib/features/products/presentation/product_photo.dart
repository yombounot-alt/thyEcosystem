import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/products_providers.dart';
import '../data/product_models.dart';

/// The photo bytes of [product], or null while loading / when it has none / when loading failed.
Uint8List? _photoBytes(WidgetRef ref, Product product) {
  final key = product.imageKey;
  if (key == null) return null;
  return ref.watch(productImageProvider((productId: product.id, imageKey: key))).value;
}

/// Round picture for lists: the product's photo, or its initial when there is none.
class ProductAvatar extends ConsumerWidget {
  const ProductAvatar({super.key, required this.product, this.radius = 20});

  final Product product;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = _photoBytes(ref, product);

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      backgroundImage: bytes == null ? null : MemoryImage(bytes),
      child:
          bytes == null
              ? Text(
                product.name.isEmpty ? '?' : product.name.characters.first.toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              )
              : null,
    );
  }
}

/// Rounded rectangle showing a photo, cropped to fill.
class PhotoFrame extends StatelessWidget {
  const PhotoFrame({super.key, this.bytes, this.width, this.height = 180, this.placeholder});

  final Uint8List? bytes;
  final double? width;
  final double height;

  /// Shown when [bytes] is null (nothing chosen yet, or still loading).
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: height,
        child:
            data == null
                ? ColoredBox(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  child: Center(child: placeholder),
                )
                : Image.memory(
                  data,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder:
                      (_, _, _) => const ColoredBox(
                        color: Color(0x11000000),
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                ),
      ),
    );
  }
}

/// A product's photo, loaded through the authenticated API.
class ProductPhoto extends ConsumerWidget {
  const ProductPhoto({super.key, required this.product, this.width, this.height = 180});

  final Product product;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhotoFrame(
      bytes: _photoBytes(ref, product),
      width: width,
      height: height,
      placeholder: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
