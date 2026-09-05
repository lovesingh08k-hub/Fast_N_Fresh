import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../dashboard/dashboard_screen.dart';
import '../pos/new_order_screen.dart';
import '../orders/orders_screen.dart';
import '../customers/customers_screen.dart';
import '../settings/more_screen.dart';
import '../settings/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // The staff app is behind a login, so the first time MainShell builds
    // (i.e. right after sign-in, or on a restored session) is the right
    // moment to ask for the notification permission used for new-order
    // alerts, and to register this device for push notifications so new
    // orders still alert admin/manager/staff even when the app is fully
    // closed.
    NotificationService.instance.init().then(
          (_) => NotificationService.instance.requestPermission(),
        );
    PushNotificationService.instance.registerDeviceToken();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final refreshTick = context.watch<TabRefreshBus>().appRefreshTick;
    // Admin AND Manager get the Dashboard + More tabs; the More screen itself
    // shows different sections depending on which of the two is logged in.
    final showDashboardAndMore = user?.canViewDashboard ?? false;

    final pages = showDashboardAndMore
        ? [
            DashboardScreen(key: ValueKey('dashboard-$refreshTick')),
            NewOrderScreen(key: ValueKey('pos-$refreshTick')),
            OrdersScreen(key: ValueKey('orders-$refreshTick')),
            CustomersScreen(key: ValueKey('customers-$refreshTick')),
            MoreScreen(key: ValueKey('more-$refreshTick')),
          ]
        : [
            NewOrderScreen(key: ValueKey('pos-$refreshTick')),
            OrdersScreen(key: ValueKey('orders-$refreshTick')),
            CustomersScreen(key: ValueKey('customers-$refreshTick')),
            ProfileScreen(key: ValueKey('profile-$refreshTick')),
          ];

    final items = showDashboardAndMore
        ? const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_outlined), activeIcon: Icon(Icons.point_of_sale), label: 'POS'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Customers'),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz), activeIcon: Icon(Icons.more_horiz), label: 'More'),
          ]
        : const [
            BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_outlined), activeIcon: Icon(Icons.point_of_sale), label: 'POS'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Customers'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
          ];

    // Staff should land directly on the New Order / POS tab after login.
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          setState(() => _index = i);
          if (showDashboardAndMore && i == 0) {
            context.read<TabRefreshBus>().bumpDashboard();
          }
        },
        items: items,
      ),
    );
  }
}
