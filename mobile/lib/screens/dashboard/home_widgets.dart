import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/pos_ui.dart';
import '../../core/widgets/product_image.dart';
import '../../models/dashboard_models.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../pos/counter_slots_screen.dart';
import '../tables/tables_screen.dart';

/// Pieces of the redesigned Home screen.

/// Business logo/initial, outlet name and the header buttons.
class HomeHeader extends StatelessWidget {
  final List<Widget> actions;

  const HomeHeader({super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = auth.session;
    final outlet = session?.currentOutlet?.name;
    final business = session?.name ?? 'PWP POS';
    final title = outlet ?? business;
    final subtitle = outlet != null && outlet != business ? business : 'Point of Sale';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: FreshUi.greenGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            title.trim().isEmpty ? 'P' : title.trim()[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Round header icon button (search, theme, refresh).
class HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget? child;

  const HeaderCircleButton({super.key, required this.icon, required this.tooltip, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: AppColors.surface,
          shape: CircleBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(child: child ?? Icon(icon, size: 20, color: AppColors.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Good morning, Ravi 👋" with a one-line tip.
class HomeGreeting extends StatelessWidget {
  final String userName;

  const HomeGreeting({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour >= 4 && hour < 12
        ? 'Good morning'
        : hour >= 12 && hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final first = userName.trim().split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$greeting, $first 👋',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.3, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text('Serve every guest with a smile today.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Small up/down change vs. yesterday ("▲ 12% from yesterday").
class TrendChip extends StatelessWidget {
  final double today;
  final double? yesterday;
  final bool onDark;

  const TrendChip({super.key, required this.today, required this.yesterday, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final y = yesterday;
    if (y == null || y <= 0) {
      return Text('No sales yesterday', style: TextStyle(fontSize: 11.5, color: onDark ? Colors.white70 : AppColors.textMuted));
    }
    final change = ((today - y) / y * 100);
    final up = change >= 0;
    final color = onDark ? Colors.white : (up ? AppColors.success : AppColors.danger);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: onDark ? Colors.white.withValues(alpha: .2) : color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: color),
              const SizedBox(width: 3),
              Text('${change.abs().toStringAsFixed(0)}%', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text('from yesterday', style: TextStyle(fontSize: 11.5, color: onDark ? Colors.white70 : AppColors.textMuted)),
      ],
    );
  }
}

/// Big brand card with today's sales.
class TodaySalesCard extends StatelessWidget {
  final PeriodSummary today;
  final double? yesterdaySales;

  const TodaySalesCard({super.key, required this.today, this.yesterdaySales});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8257), Color(0xFFF2643D), Color(0xFFE2522E)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFFF2643D).withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -18,
            child: Icon(Icons.currency_rupee_rounded, size: 120, color: Colors.white.withValues(alpha: .10)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text("Today's Sales", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(20)),
                    child: Text('${today.orders} bills',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Formatters.currency(today.sales),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -.5),
                ),
              ),
              const SizedBox(height: 8),
              TrendChip(today: today.sales, yesterday: yesterdaySales, onDark: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  _pay('Cash', today.cash),
                  _pay('UPI', today.upi),
                  _pay('Credit', today.credit),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pay(String label, double amount) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(Formatters.currency(amount),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ],
        ),
      );
}

/// White stat card: icon, label, big number and a small note.
class MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String note;
  final VoidCallback? onTap;

  const MiniStatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: FreshUi.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 4),
              Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round shortcut buttons: Dine-in, Takeaway, Delivery, QR orders.
class QuickActions extends StatelessWidget {
  final VoidCallback? onOrders;

  const QuickActions({super.key, this.onOrders});

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    final actions = [
      ('Dine-in', Icons.table_restaurant_rounded, const Color(0xFFF2643D), () => push(const TablesScreen())),
      ('Takeaway', Icons.shopping_bag_rounded, const Color(0xFF3B82F6), () => push(const CounterSlotsScreen(orderType: 'takeaway'))),
      ('Delivery', Icons.delivery_dining_rounded, const Color(0xFF8B5CF6), () => push(const CounterSlotsScreen(orderType: 'delivery'))),
      ('Orders', Icons.receipt_long_rounded, const Color(0xFF1FA463), onOrders ?? () {}),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: FreshUi.card(),
      child: Row(
        children: [
          for (final a in actions)
            Expanded(
              child: InkWell(
                onTap: a.$4,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: a.$3.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
                        child: Icon(a.$2, color: a.$3, size: 24),
                      ),
                      const SizedBox(height: 6),
                      Text(a.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal cards of today's best sellers, with menu photo/tile and price.
class PopularDishes extends StatelessWidget {
  final List<TopProduct> products;

  const PopularDishes({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<CatalogProvider>().products;
    Product? find(String name) {
      for (final p in menu) {
        if (p.name == name) return p;
      }
      return null;
    }

    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: FreshUi.card(),
        child: Row(
          children: [
            const Text('🍽️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Your best sellers of the day will appear here after the first bills.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final top = products[i];
          final item = find(top.name);
          return Container(
            width: 150,
            padding: const EdgeInsets.all(8),
            decoration: FreshUi.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ProductImage(
                      name: top.name,
                      imageUrl: item?.imageUrl ?? '',
                      width: 134,
                      height: 104,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                        child: Text('#${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item != null && item.foodType.isNotEmpty) ...[
                      FoodTypeMark(foodType: item.foodType, size: 12),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(top.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item != null)
                      Text(Formatters.currency(item.sellingPrice),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const Spacer(),
                    Text('${top.quantitySold} sold', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
