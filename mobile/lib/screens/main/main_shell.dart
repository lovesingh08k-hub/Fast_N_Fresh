import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../../models/user.dart';
import '../dashboard/dashboard_screen.dart';
import '../orders/orders_screen.dart';
import '../orders/bill_history_screen.dart';
import '../customers/customers_screen.dart';
import '../settings/more_screen.dart';
import '../pos/new_order_screen.dart';
import '../settings/profile_screen.dart';

/// App-wide navigation shell.
///
/// The POS deliberately keeps navigation shallow: the primary actions are
/// always one tap away, while administration/configuration lives under
/// Workspace. This avoids repeating the same action rows on every screen.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final AppUser _user;
  late final List<_NavItem> _items;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _user = context.read<AuthProvider>().currentUser!;
    _items = _buildNavigation(_user);
    _pages = _items.map((item) => item.page).toList(growable: false);
  }

  List<_NavItem> _buildNavigation(AppUser user) {
    if (user.canViewDashboard) {
      return [
        _NavItem('Home', Icons.grid_view_rounded, Icons.grid_view_rounded, const DashboardScreen()),
        _NavItem('New Sale', Icons.add_circle_outline_rounded, Icons.add_circle_rounded, const NewOrderScreen()),
        _NavItem('Orders', Icons.receipt_long_outlined, Icons.receipt_long_rounded, const OrdersScreen()),
        _NavItem('Bills', Icons.receipt_long_outlined, Icons.receipt_long_rounded, const BillHistoryScreen()),
        _NavItem('Workspace', Icons.apps_outlined, Icons.apps_rounded, const MoreScreen()),
      ];
    }

    // Staff should spend almost all of their time in POS / orders.
    // Customers and profile remain available from Workspace rather than
    // consuming permanent bottom-navigation space.
    return [
      _NavItem('New Sale', Icons.add_circle_outline_rounded, Icons.add_circle_rounded, const NewOrderScreen()),
      _NavItem('Orders', Icons.receipt_long_outlined, Icons.receipt_long_rounded, const OrdersScreen()),
      _NavItem('Workspace', Icons.apps_outlined, Icons.apps_rounded, const MoreScreen()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      body: Row(
        children: [
          if (isWide) _buildRail(context),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide ? null : _buildBottomBar(context),
    );
  }

  Widget _buildRail(BuildContext context) {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Image.asset('assets/images/app_icon.png'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _railItem(context, i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.primaryLight,
                foregroundColor: AppColors.primary,
                child: Text(
                  _user.name.isEmpty ? '?' : _user.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railItem(BuildContext context, int index) {
    final selected = _index == index;
    final item = _items[index];
    return Tooltip(
      message: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 58,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(selected ? item.selectedIcon : item.icon,
              color: selected ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          height: 70,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.primaryLight,
          selectedIndex: _index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: _select,
          destinations: _items
              .map((item) => NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    if (_items[index].label == 'Home') {
      context.read<TabRefreshBus>().bumpDashboard();
    }
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const _NavItem(this.label, this.icon, this.selectedIcon, this.page);
}
