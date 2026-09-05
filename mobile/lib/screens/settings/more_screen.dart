import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../products/products_screen.dart';
import '../inventory/inventory_screen.dart';
import '../staff/staff_screen.dart';
import '../reports/reports_screen.dart';
import '../expenses/expenses_screen.dart';
import '../settings/settings_screen.dart';
import '../categories/categories_screen.dart';
import '../tables/tables_screen.dart';
import '../users/users_screen.dart';
import '../attendance/attendance_screen.dart';
import '../orders/kitchen_screen.dart';
import 'change_password_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isAdmin = user?.isAdmin ?? false;
    final isManager = user?.isManager ?? false;

    // Operational items both Admin and Manager see.
    final items = <_MenuItem>[
      _MenuItem(
        'Tables',
        Icons.table_restaurant_outlined,
        (ctx) => TablesScreen(),
      ),
      _MenuItem(
        'Inventory',
        Icons.inventory_2_outlined,
        (ctx) => InventoryScreen(),
      ),
    ];

    if (isAdmin) {
      // Admin-only sections.
      items.addAll([
        _MenuItem(
          'Products',
          Icons.fastfood_outlined,
          (ctx) => ProductsScreen(),
        ),
        _MenuItem(
          'Categories',
          Icons.category_outlined,
          (ctx) => CategoriesScreen(),
        ),
        _MenuItem(
          'Staff',
          Icons.badge_outlined,
          (ctx) => StaffScreen(),
        ),
        _MenuItem(
          'Users & Roles',
          Icons.admin_panel_settings_outlined,
          (ctx) => UsersScreen(),
        ),
        _MenuItem(
          'Staff Performance',
          Icons.leaderboard_outlined,
          (ctx) => AttendanceScreen(),
        ),
        _MenuItem(
          'Kitchen Display',
          Icons.restaurant_menu_outlined,
          (ctx) => KitchenScreen(),
        ),
        _MenuItem(
          'Reports',
          Icons.bar_chart_outlined,
          (ctx) => ReportsScreen(),
        ),
        _MenuItem(
          'Expenses',
          Icons.receipt_outlined,
          (ctx) => ExpensesScreen(),
        ),
        _MenuItem(
          'Settings',
          Icons.settings_outlined,
          (ctx) => SettingsScreen(),
        ),
      ]);
    } else if (isManager) {
      // Manager gets operational access + Credit / UDHAR report.
      items.add(
        _MenuItem(
          'Credit / UDHAR Report',
          Icons.account_balance_wallet_outlined,
          (ctx) => ReportsScreen(creditOnly: true),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('More'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    user?.name.isNotEmpty == true
                        ? user!.name[0].toUpperCase()
                        : 'A',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        isAdmin ? 'Administrator' : 'Manager',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          ...items.map(
            (item) => _buildTile(context, item),
          ),

          SizedBox(height: 12),

          _buildTile(
            context,
            _MenuItem(
              'Change Password',
              Icons.lock_outline,
              (ctx) => ChangePasswordScreen(),
            ),
          ),

          SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: Icon(
              Icons.logout,
              color: AppColors.danger,
              size: 18,
            ),
            label: Text(
              'Logout',
              style: TextStyle(
                color: AppColors.danger,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    _MenuItem item,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: AppColors.textSecondary,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: AppColors.textMuted,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: item.builder,
            ),
          );
        },
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  _MenuItem(
    this.label,
    this.icon,
    this.builder,
  );
}