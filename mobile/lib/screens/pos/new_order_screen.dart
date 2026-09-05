import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/cart_provider.dart';
import '../tables/tables_screen.dart';
import 'pos_screen.dart';

/// Entry point for starting any new order.
///
/// Dine-In -> Table selection
/// Takeaway -> POS
/// Delivery -> POS
class NewOrderScreen extends StatelessWidget {
  const NewOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Order'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What type of order is this?',
              style: Theme.of(context).textTheme.titleLarge,
            ),

            SizedBox(height: 6),

            Text(
              'Choose how this customer is being served.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            SizedBox(height: 24),

            // --------------------------------------------------
            // DINE-IN
            // --------------------------------------------------
            _OrderTypeCard(
              icon: Icons.restaurant_outlined,
              title: 'Dine-In',
              subtitle: 'Customer is seated at a table',
              color: AppColors.primary,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TablesScreen(),
                  ),
                );
              },
            ),

            SizedBox(height: 12),

            // --------------------------------------------------
            // TAKEAWAY
            // --------------------------------------------------
            _OrderTypeCard(
              icon: Icons.shopping_bag_outlined,
              title: 'Takeaway',
              subtitle: 'Customer will pick up the order',
              color: AppColors.info,
              onTap: () {
                context.read<CartProvider>().clear();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PosScreen(
                      orderType: 'takeaway',
                    ),
                  ),
                );
              },
            ),

            SizedBox(height: 12),

            // --------------------------------------------------
            // DELIVERY
            // --------------------------------------------------
            _OrderTypeCard(
              icon: Icons.delivery_dining_outlined,
              title: 'Delivery',
              subtitle: 'Order will be delivered to the customer',
              color: AppColors.accent,
              onTap: () {
                context.read<CartProvider>().clear();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PosScreen(
                      orderType: 'delivery',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ORDER TYPE CARD
// ============================================================

class _OrderTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _OrderTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 26,
              ),
            ),

            SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),

                  SizedBox(height: 3),

                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}