import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../attendance/attendance_screen.dart';
import '../categories/categories_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../inventory/inventory_screen.dart';
import '../orders/bill_history_screen.dart';
import '../pos/new_order_screen.dart';
import '../products/products_screen.dart';
import '../reports/reports_screen.dart';
import '../staff/staff_screen.dart';
import '../tables/tables_screen.dart';
import '../users/users_screen.dart';
import 'change_password_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'manager_center_screen.dart';
import 'audit_log_screen.dart';
import '../products/recipe_manager_screen.dart';

/// Role-aware workspace. It is intentionally compact: users see tools grouped
/// by the job they perform instead of a long list of repeated tiles.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => _open(context, const ProfileScreen()),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          _buildProfileHeader(context, user),
          const SizedBox(height: 20),
          if (user.isAdmin || user.isManager) ...[
            _section(
              context,
              title: 'Operations',
              subtitle: 'Run the floor without leaving the workspace',
              items: [
                _Tool('New sale', Icons.add_circle_outline_rounded, const NewOrderScreen()),
                _Tool('Bills', Icons.receipt_long_rounded, const BillHistoryScreen()),
                _Tool('Tables', Icons.table_restaurant_outlined, const TablesScreen()),
                _Tool('Customers', Icons.people_outline_rounded, const CustomersScreen()),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (user.isAdmin || user.isManager) ...[
            _section(
              context,
              title: 'Business',
              subtitle: 'Products, stock, reports and daily controls',
              items: [
                _Tool('Inventory', Icons.inventory_2_outlined, InventoryScreen()),
                _Tool('Recipes', Icons.restaurant_menu_outlined, const RecipeManagerScreen()),
                _Tool('Products', Icons.fastfood_outlined, const ProductsScreen()),
                _Tool('Manager Center', Icons.manage_accounts_outlined, const ManagerCenterScreen()),
                _Tool('Audit Log', Icons.history_rounded, const AuditLogScreen()),
                _Tool('Reports', Icons.insights_outlined, ReportsScreen()),
                if (user.isAdmin) _Tool('Expenses', Icons.receipt_long_outlined, ExpensesScreen()),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (user.isAdmin) ...[
            _section(
              context,
              title: 'Administration',
              subtitle: 'People, access and business configuration',
              items: [
                _Tool('Staff', Icons.badge_outlined, StaffScreen()),
                _Tool('Users & roles', Icons.admin_panel_settings_outlined, UsersScreen()),
                _Tool('Staff performance', Icons.leaderboard_outlined, AttendanceScreen()),
                _Tool('Categories', Icons.category_outlined, CategoriesScreen()),
                _Tool('Settings', Icons.settings_outlined, SettingsScreen()),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (user.isStaff) ...[
            _section(
              context,
              title: 'My workspace',
              subtitle: 'Only the tools needed for your shift',
              items: [
                _Tool('Customers', Icons.people_outline_rounded, const CustomersScreen()),
                _Tool('Profile', Icons.person_outline_rounded, const ProfileScreen()),
              ],
            ),
            const SizedBox(height: 18),
          ],
          _buildAccountSection(context),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AppUser user) {
    final role = user.isAdmin ? 'Administrator' : user.isManager ? 'Manager' : 'Staff';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            child: Text(
              user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(role, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => _open(context, const ProfileScreen()),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, {
    required String title,
    required String subtitle,
    required List<_Tool> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.map((tool) => SizedBox(width: width, child: _toolCard(context, tool))).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _toolCard(BuildContext context, _Tool tool) {
    return InkWell(
      onTap: () => _open(context, tool.page),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(tool.icon, size: 19, color: AppColors.primary),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(tool.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _open(context, const ChangePasswordScreen()),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Password'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
            label: Text('Logout', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.danger)),
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
