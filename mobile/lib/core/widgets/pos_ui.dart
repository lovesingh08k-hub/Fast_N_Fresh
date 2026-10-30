import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small building blocks shared by the redesigned screens.

/// Indian food mark: a square with a dot — green (veg), red (non-veg),
/// amber (egg). Nothing is drawn when the type is unknown.
class FoodTypeMark extends StatelessWidget {
  final String foodType; // veg | non_veg | egg | ''
  final double size;

  const FoodTypeMark({super.key, required this.foodType, this.size = 14});

  static Color? colorFor(String type) => switch (type) {
        'veg' => AppColors.veg,
        'non_veg' => AppColors.nonVeg,
        'egg' => AppColors.egg,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(foodType);
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(3),
      ),
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

/// Rounded status label, e.g. "Ready", "In Progress", "Unpaid".
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Coloured rounded square with a short code ("A7", "T2", "#12").
class CodeBadge extends StatelessWidget {
  final String code;
  final Color color;
  final double size;

  const CodeBadge({super.key, required this.code, required this.color, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(code, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * .32)),
        ),
      ),
    );
  }
}

/// Section title with an optional "View all" link.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
                child: Text(action!, style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "−  2  +" quantity control; shows a single "+" when the count is zero.
class QtyStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  const QtyStepper({super.key, required this.quantity, this.onAdd, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    Widget circle(IconData icon, VoidCallback? onTap, {bool filled = true}) => Material(
          color: filled ? primary : AppColors.primaryLight,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 18, color: filled ? Colors.white : primary)),
          ),
        );

    if (quantity <= 0) return circle(Icons.add_rounded, onAdd);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle(Icons.remove_rounded, onRemove, filled: false),
        SizedBox(
          width: 30,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
          ),
        ),
        circle(Icons.add_rounded, onAdd),
      ],
    );
  }
}
