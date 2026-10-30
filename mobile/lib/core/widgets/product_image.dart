import 'package:flutter/material.dart';

import '../network/api_config.dart';
import '../theme/app_colors.dart';

/// Product photo. Items without a photo (most cafes never upload one) get a
/// warm colour tile with a dish emoji picked from the name, so menus still
/// look appetising instead of a wall of grey icons.
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

  // Keyword -> emoji, checked in order (first match wins).
  static const List<(List<String>, String)> _dishes = [
    (['pizza'], '🍕'),
    (['egg', 'omelette', 'anda', 'bhurji'], '🍳'),
    (['coffee', 'latte', 'cappuccino', 'espresso', 'americano', 'mocha'], '☕'),
    (['tea', 'chai'], '🍵'),
    (['burger'], '🍔'),
    (['sandwich', 'sub', 'wrap', 'roll', 'frankie'], '🥪'),
    (['fries', 'finger', 'wedges'], '🍟'),
    (['momo', 'dumpling', 'dimsum'], '🥟'),
    (['noodle', 'chowmein', 'maggi', 'ramen', 'hakka'], '🍜'),
    (['pasta', 'spaghetti', 'penne', 'carbonara', 'macaroni'], '🍝'),
    (['dosa', 'idli', 'uttapam', 'vada', 'appam'], '🫓'),
    (['biryani', 'pulao', 'rice', 'khichdi'], '🍛'),
    (['thali', 'curry', 'paneer', 'dal', 'masala', 'korma', 'kadai', 'sabzi', 'chole', 'rajma'], '🍛'),
    (['paratha', 'roti', 'naan', 'kulcha', 'bhatura', 'puri'], '🫓'),
    (['chicken', 'tikka', 'kebab', 'kabab', 'tandoori', 'wings'], '🍗'),
    (['fish', 'prawn', 'seafood'], '🍤'),
    (['salad'], '🥗'),
    (['soup'], '🍲'),
    (['samosa', 'pakora', 'pakoda', 'kachori', 'chaat', 'pani puri', 'golgappa', 'bhel', 'pav', 'tikki'], '🥘'),
    (['cake', 'pastry', 'brownie', 'muffin', 'cupcake'], '🍰'),
    (['ice cream', 'icecream', 'sundae', 'kulfi', 'gelato'], '🍨'),
    (['shake', 'smoothie', 'lassi', 'frappe'], '🥤'),
    (['mojito', 'mocktail', 'lemonade', 'cooler', 'soda', 'juice', 'cola', 'drink'], '🍹'),
    (['water'], '💧'),
    (['sweet', 'gulab', 'rasgulla', 'jalebi', 'halwa', 'barfi', 'ladoo', 'kheer'], '🍮'),
    (['toast', 'bread', 'bun', 'garlic'], '🍞'),
    (['packag', 'parcel', 'container'], '📦'),
  ];

  // Warm tile colours (light, dark) picked by the name.
  static const List<(Color, Color)> _tints = [
    (Color(0xFFFFEDE7), Color(0xFF3A2219)),
    (Color(0xFFFFF4DB), Color(0xFF3A2E14)),
    (Color(0xFFE9F7EF), Color(0xFF173225)),
    (Color(0xFFFDEBF1), Color(0xFF3A1A26)),
    (Color(0xFFEFEDFF), Color(0xFF241F3D)),
    (Color(0xFFE7F3FF), Color(0xFF16283D)),
  ];

  static String emojiFor(String name) {
    final n = name.toLowerCase();
    for (final (keys, emoji) in _dishes) {
      if (keys.any(n.contains)) return emoji;
    }
    return '🍽️';
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholder();
    final url = imageUrl.trim();
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                ApiConfig.resolveAssetUrl(url),
                fit: fit,
                width: width,
                height: height,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
              ),
      ),
    );
  }

  Widget _placeholder() {
    final (light, dark) = _tints[name.hashCode.abs() % _tints.length];
    final tile = Color.lerp(light, dark, AppColors.progress.value)!;
    final size = (width ?? height ?? 56);
    return Container(
      width: width,
      height: height,
      color: tile,
      alignment: Alignment.center,
      child: Text(emojiFor(name), style: TextStyle(fontSize: (size * .46).clamp(16, 54))),
    );
  }
}
