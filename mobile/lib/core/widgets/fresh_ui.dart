import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared look for the redesigned screens: white rounded cards with a soft
/// shadow on a light grey page, saffron-coral brand accents, green for
/// "available/success". Background/surface/text come from [AppColors].
class FreshUi {
  FreshUi._();

  /// Brand accent (saffron-coral). The name is kept from the old palette.
  static const Color mint = Color(0xFFF2643D);
  static const Color mintBright = Color(0xFFFF7A52);
  static const Color green = Color(0xFF1FA463);
  static const Color amber = Color(0xFFF59E0B);
  static const Color red = Color(0xFFE5484D);

  /// Main call-to-action fill (brand).
  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF7A52), Color(0xFFF2643D)],
  );

  static const LinearGradient redGradient = LinearGradient(
    colors: [Color(0xFFEF5A5F), Color(0xFFE5484D)],
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFFFBB33A), Color(0xFFF59E0B)],
  );

  /// Soft shadow under white cards (none in dark mode).
  static List<BoxShadow> get shadow => [
        BoxShadow(color: AppColors.cardShadow, blurRadius: 18, offset: const Offset(0, 6)),
      ];

  /// White rounded card with a soft shadow; [tint] adds a faint colour wash
  /// and border (used for status-coloured cards).
  static BoxDecoration card({Color? tint, double radius = 18, double tintStrength = 0}) {
    return BoxDecoration(
      color: tint != null && tintStrength > 0
          ? Color.alphaBlend(tint.withValues(alpha: tintStrength), AppColors.surface)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: tint != null && tintStrength > 0 ? tint.withValues(alpha: .25) : AppColors.border),
      boxShadow: shadow,
    );
  }
}

/// Page title with an optional leading icon or back arrow, an optional
/// subtitle and trailing action buttons.
class FreshHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool showBack;
  final List<Widget> actions;

  const FreshHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.showBack = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: FreshUi.mint, size: 22),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(icon, color: FreshUi.mint, size: 24),
          ),
        if (showBack) const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: showBack ? 19 : 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Header action icon in the page title row.
class FreshHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const FreshHeaderAction({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 22, color: AppColors.textPrimary),
    );
  }
}

/// Full-width button used on cards ("Start Order", "View Order").
class FreshGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onPressed;
  final double height;

  const FreshGradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.gradient = FreshUi.greenGradient,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(10),
          ),
          // On narrow two-column phone grids, drop the chevron so the label
          // ("Start Order") is not ellipsized.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 150;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!compact) ...[
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Small round outlined icon button (edit / view on list rows).
class FreshCircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const FreshCircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: size * .5, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
