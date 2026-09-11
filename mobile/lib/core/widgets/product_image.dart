import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Product visual placeholder. Food photos are intentionally disabled across
/// the POS so the catalog stays fast and text-first. The product image URL is
/// still accepted for backwards compatibility with existing models/APIs.
class ProductImage extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const ProductImage({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: width,
        height: height,
        color: AppColors.background,
        alignment: Alignment.center,
        child: Icon(
          Icons.fastfood_outlined,
          size: ((width ?? 48) * .38).clamp(18, 28),
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
