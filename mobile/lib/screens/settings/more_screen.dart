import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/outlet_switcher.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../attendance/attendance_screen.dart';
import '../categories/categories_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../inventory/inventory_screen.dart';
import '../orders/kitchen_screen.dart';
import '../products/products_screen.dart';
import '../reports/reports_screen.dart';
import '../staff/staff_screen.dart';
import '../tables/qr_management_screen.dart';
import '../tables/tables_screen.dart';
import '../users/users_screen.dart';
import 'archive_screen.dart';
import 'change_password_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// Simple role-aware menu. The main navigation already exposes Home, New Sale,
/// Orders and Bills, so this screen only contains tools that are not needed on
/// every transaction. This keeps the staff workflow fast and reduces duplicate
/// taps.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            FreshHeader(
              title: 'More',
              actions: [
                FreshHeaderAction(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Profile',
                  onPressed: () => _open(context, const ProfileScreen()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildProfileHeader(context, user),
            const OutletSwitcherCard(),
            const SizedBox(height: 18),
            if (user.isAdmin || user.isManager) ...[
              _section(
                title: 'Daily Operations',
                items: [
                  const _Tool('Tables', Icons.table_restaurant_outlined, TablesScreen()),
                  const _Tool('Kitchen', Icons.restaurant_outlined, KitchenScreen()),
                  const _Tool('Customers', Icons.people_alt_outlined, CustomersScreen()),
                  const _Tool('QR Ordering', Icons.qr_code_2_rounded, QrManagementScreen()),
                ],
              ),
              _section(
                title: 'Products & Stock',
                items: [
                  const _Tool('Products', Icons.room_service_outlined, ProductsScreen()),
                  const _Tool('Categories', Icons.category_outlined, CategoriesScreen()),
                  const _Tool('Inventory', Icons.inventory_2_outlined, InventoryScreen()),
                ],
              ),
              _section(
                title: 'Business',
                items: [
                  const _Tool('Reports', Icons.trending_up_rounded, ReportsScreen()),
                  if (user.isAdmin) const _Tool('Expenses', Icons.request_quote_outlined, ExpensesScreen()),
                ],
              ),
            ],
            if (user.isAdmin)
              _section(
                title: 'Administration',
                items: [
                  const _Tool('Staff', Icons.badge_outlined, StaffScreen()),
                  const _Tool('Users & Roles', Icons.admin_panel_settings_outlined, UsersScreen()),
                  const _Tool('Staff Performance', Icons.leaderboard_outlined, AttendanceScreen()),
                  const _Tool('Settings', Icons.settings_outlined, SettingsScreen()),
                  const _Tool('Data & Storage', Icons.storage_rounded, ArchiveScreen()),
                ],
              ),
            if (user.isStaff)
              _section(
                title: 'My Tools',
                items: [
                  const _Tool('Customers', Icons.people_alt_outlined, CustomersScreen()),
                  const _Tool('Profile', Icons.person_outline_rounded, ProfileScreen()),
                ],
              ),
            const SizedBox(height: 4),
            _buildAccountSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AppUser user) {
    final role = user.isAdmin ? 'Administrator' : user.isManager ? 'Manager' : 'Staff';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context, const ProfileScreen()),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: FreshUi.card(tintStrength: .08),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: FreshUi.mint,
                foregroundColor: Colors.white,
                child: Text(
                  user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    Text(role, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required List<_Tool> items}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: AppColors.textMuted,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 700 ? 4 : 2;
              const gap = 8.0;
              final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items
                    .map((tool) => SizedBox(width: width, child: _toolCard(context, tool)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _toolCard(BuildContext context, _Tool tool) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context, tool.page),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: FreshUi.mint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(tool.icon, size: 18, color: FreshUi.mint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tool.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const size = Size.fromHeight(42);
    const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _open(context, const ChangePasswordScreen()),
            icon: Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textPrimary),
            label: Text('Password', style: label.copyWith(color: AppColors.textPrimary)),
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              shape: shape,
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
            label: Text('Logout', style: label.copyWith(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              shape: shape,
              side: BorderSide(color: AppColors.danger.withValues(alpha: .6)),
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _Tool {
  final String label;
  final IconData icon;
  final Widget page;
  const _Tool(this.label, this.icon, this.page);
}
