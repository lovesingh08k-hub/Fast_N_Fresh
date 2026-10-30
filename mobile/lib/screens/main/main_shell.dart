import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../../models/user.dart';
import '../dashboard/dashboard_screen.dart';
import '../orders/orders_screen.dart';
import '../orders/bill_history_screen.dart';
import '../settings/more_screen.dart';
import '../pos/new_order_screen.dart';
import '../../services/app_update_service.dart';

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

  /// Tab the app opens on and back returns to: Home, or New Sale for staff.
  int _homeIndex = 0;
  late final AppUser _user;
  late final List<_NavItem> _items;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _user = context.read<AuthProvider>().currentUser!;
    _items = _buildNavigation(_user);
    _pages = _items.map((item) => item.page).toList(growable: false);
    _homeIndex = _user.canViewDashboard ? 0 : _items.indexWhere((item) => item.label == 'New Sale');
    _index = _homeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A new shell means a new login or outlet: drop the previous outlet's
      // menu and cart.
      context.read<CatalogProvider>().reset();
      context.read<CartProvider>().clear();
      _checkForAvailableUpdate();
    });
  }

  Future<void> _checkForAvailableUpdate() async {
    // Updates are distributed as an APK, which only Android can install.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final result = await AppUpdateService.instance.checkForUpdate();
      if (!mounted || !result.hasUpdate) return;

      final update = result.update!;
      final shouldUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.forceUpdate,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New PWP POS update'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Version ${update.version} (${update.buildNumber})', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (update.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(update.notes.trim()),
                ],
                const SizedBox(height: 14),
                const Text('Download the latest APK and install it when Android asks for confirmation.'),
              ],
            ),
          ),
          actions: [
            if (!update.forceUpdate)
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Later')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Update Now'),
            ),
          ],
        ),
      );

      if (shouldUpdate == true) {
        await AppUpdateService.instance.openDownload(update.downloadUrl);
      }
    } catch (_) {
      // Update checks are non-blocking. The POS continues normally when the
      // backend is sleeping, offline, or update metadata is not configured.
    }
  }

  List<_NavItem> _buildNavigation(AppUser user) {
    if (user.canViewDashboard) {
      return [
        // "New Sale" sits in the middle as the raised round button.
        const _NavItem('Home', Icons.home_outlined, Icons.home_rounded, DashboardScreen()),
        const _NavItem('Orders', Icons.table_restaurant_outlined, Icons.table_restaurant_rounded, OrdersScreen()),
        const _NavItem('New Sale', Icons.add_rounded, Icons.add_rounded, NewOrderScreen()),
        const _NavItem('Bills', Icons.receipt_long_outlined, Icons.receipt_long_rounded, BillHistoryScreen()),
        const _NavItem('More', Icons.grid_view_outlined, Icons.grid_view_rounded, MoreScreen()),
      ];
    }

    // Staff should spend almost all of their time in POS / orders.
    // Customers and profile remain available from Workspace rather than
    // consuming permanent bottom-navigation space.
    return [
      const _NavItem('Orders', Icons.table_restaurant_outlined, Icons.table_restaurant_rounded, OrdersScreen()),
      const _NavItem('New Sale', Icons.add_rounded, Icons.add_rounded, NewOrderScreen()),
      const _NavItem('More', Icons.grid_view_outlined, Icons.grid_view_rounded, MoreScreen()),
    ];
  }

  DateTime? _lastBackPress;

  /// Android back on the shell itself (pushed pages above it pop normally):
  /// another tab -> first tab; first tab -> "press back again to exit", so
  /// a single back press never closes the whole app by accident.
  void _onBackPressed() {
    if (_index != _homeIndex) {
      _select(_homeIndex);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: _buildScaffold(context, isWide),
    );
  }

  Widget _buildScaffold(BuildContext context, bool isWide) {
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
    final centre = _items.indexWhere((item) => item.label == 'New Sale');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 24, offset: const Offset(0, -6))],
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(child: i == centre ? _centreButton(i) : _tab(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int index) {
    final item = _items[index];
    final selected = _index == index;
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return InkWell(
      onTap: () => _select(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 23),
          ),
          const SizedBox(height: 3),
          Text(item.label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _centreButton(int index) {
    final selected = _index == index;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: 'New Sale',
          child: Material(
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _select(index),
              child: Ink(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: FreshUi.greenGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: selected ? .45 : .30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
      ],
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
