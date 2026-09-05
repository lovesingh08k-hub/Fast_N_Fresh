import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/dashboard_models.dart';
import '../../services/dashboard_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../../widgets/stat_card.dart';
import '../orders/order_detail_screen.dart';
import '../../services/order_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final _dashboardService = DashboardService();

  // The Dashboard is backed by TWO independent backend calls
  // (GET /dashboard and GET /dashboard/sales-overview). They are loaded
  // and error-handled independently on purpose: previously a single
  // Future.wait() meant either call failing took the WHOLE dashboard down.
  // Now, e.g., a slow sales-overview call never hides an already-loaded
  // stats grid / recent orders / top products, and vice versa.
  //
  // `null` means "no data for this section yet" (or every attempt so far
  // has failed) -- as opposed to a successful response, which is never
  // null. A failed *refresh* of a section that already has data keeps
  // showing that data with a small inline retry banner instead of
  // blanking the section.
  DashboardData? _data;
  SalesOverview? _overview;

  bool _loadingStats = true;
  bool _loadingOverview = true;

  String? _statsError;
  String? _overviewError;

  String _overviewTab = 'Today';

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  TabRefreshBus? _tabRefreshBus;
  Timer? _refreshTimer;
  int? _lastDashboardTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // QR orders are created outside the staff app, so the dashboard must
    // refresh periodically instead of waiting for the user to revisit the
    // tab. This keeps the Orders card and Recent Orders live.
    _refreshTimer = Timer.periodic(Duration(seconds: 8), (_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final connectivity = context.read<ConnectivityProvider>();
    if (!identical(connectivity, _connectivity)) {
      _connectivity?.removeListener(_handleConnectivityChange);
      _connectivity = connectivity;
      _wasOnline = connectivity.isOnline;
      _connectivity!.addListener(_handleConnectivityChange);
    }

    // `MainShell` keeps this screen alive via `IndexedStack`, so `_load()`
    // above only ever runs once. Re-fetch whenever the user taps back into
    // the Dashboard tab so newly placed/updated orders show up promptly
    // instead of showing whatever was loaded the first time.
    final tabRefreshBus = context.read<TabRefreshBus>();
    if (!identical(tabRefreshBus, _tabRefreshBus)) {
      _tabRefreshBus = tabRefreshBus;
      _lastDashboardTick = tabRefreshBus.dashboardTick;
      _tabRefreshBus!.addListener(_handleTabRefresh);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    _tabRefreshBus?.removeListener(_handleTabRefresh);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _handleTabRefresh() {
    final tick = _tabRefreshBus?.dashboardTick;
    if (tick != null && tick != _lastDashboardTick) {
      _lastDashboardTick = tick;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && mounted && (_statsError != null || _overviewError != null)) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && (_statsError != null || _overviewError != null)) {
      _load();
    }

    _wasOnline = isOnline;
  }

  /// Refreshes both sections. They run independently (not Future.wait),
  /// so one failing can never hide a successful response from the other.
  Future<void> _load() async {
    await Future.wait([
      _loadStats(),
      _loadOverview(),
    ]);
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);

    try {
      final data = await _dashboardService.getDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
        _statsError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // `_data` is deliberately left untouched on failure so a previously
      // loaded stats grid / alerts / recent orders / top products stay on
      // screen with an inline retry banner instead of disappearing.
      setState(() => _statsError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _statsError = 'Could not load dashboard stats.');
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);

    try {
      final overview = await _dashboardService.getSalesOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _overviewError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _overviewError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _overviewError = 'Could not load sales overview.');
    } finally {
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  Future<void> _refreshWholeApp() async {
    final bus = context.read<TabRefreshBus>();
    await bus.refreshWholeApp(
      beforeRebuild: () async {
        await Future.wait([
          context.read<AuthProvider>().checkSessionOnResume(),
          context.read<CatalogProvider>().load(),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName =
        context.watch<AuthProvider>().currentUser?.name ?? 'Admin';

    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');

    // Only when BOTH sections have never loaded anything at all do we show
    // a full-page state. Any other combination (one loaded, one didn't;
    // both loaded; one still loading) renders the normal scrollable
    // layout with each section handling its own state -- the Dashboard
    // itself, its greeting, and the bottom navigation stay visible and
    // usable throughout.
    final nothingLoadedYet = _data == null && _overview == null;
    final stillLoadingEverything = _loadingStats && _loadingOverview;
    final everythingFailed = !_loadingStats &&
        !_loadingOverview &&
        _statsError != null &&
        _overviewError != null;

    Widget body;

    if (nothingLoadedYet && stillLoadingEverything) {
      body = LoadingState();
    } else if (nothingLoadedYet && everythingFailed) {
      body = ErrorState(
        message: _statsError ?? _overviewError ?? 'Could not load the dashboard.',
        onRetry: _load,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24,
          ),
          children: [
            Text(
              '$greeting, $userName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),

            SizedBox(height: 16),

            _buildStatsBlock(),

            SizedBox(height: 20),

            _buildSalesOverviewBlock(),

            SizedBox(height: 20),

            _buildOrdersAndProductsBlock(),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('FAST N FRESH CAFE'),
        actions: [
          PopupMenuButton<AppThemeMode>(
            tooltip: 'Appearance',
            icon: const Icon(Icons.brightness_6_outlined),
            onSelected: (mode) => context.read<ThemeProvider>().setMode(mode),
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppThemeMode.system, child: Text('System')),
              PopupMenuItem(value: AppThemeMode.light, child: Text('Light')),
              PopupMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
            ],
          ),
          Consumer<TabRefreshBus>(
            builder: (_, bus, __) => IconButton(
              tooltip: 'Refresh entire app',
              onPressed: bus.isRefreshing ? null : _refreshWholeApp,
              icon: bus.isRefreshing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  // ---------------------------------------------------------------------------
  // STATS + ALERTS (from GET /dashboard) -- one independent section
  // ---------------------------------------------------------------------------

  Widget _buildStatsBlock() {
    if (_data != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statsError != null) ...[
            InlineRetryBanner(
              message: 'Could not refresh stats. Showing last known data.',
              onRetry: _loadStats,
            ),
            SizedBox(height: 12),
          ],
          _buildStatsGrid(),
          SizedBox(height: 20),
          _buildAlerts(),
        ],
      );
    }

    if (_loadingStats) {
      return SectionLoadingBox(height: 220);
    }

    return SectionErrorBox(
      message: _statsError ?? 'Could not load dashboard stats.',
      onRetry: _loadStats,
    );
  }

  Widget _buildStatsGrid() {
    final d = _data!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final isVerySmallPhone = width < 340;
        final isSmallPhone = width >= 340 && width < 390;

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),

          crossAxisSpacing: 12,
          mainAxisSpacing: 12,

          // More vertical space on smaller screens.
          childAspectRatio: isVerySmallPhone
              ? 1.05
              : isSmallPhone
                  ? 1.15
                  : 1.40,

          children: [
            StatCard(
              label: "Today's Sales",
              value: Formatters.currency(d.today.sales),
              icon: Icons.payments_outlined,
              accentColor: AppColors.primary,
            ),

            StatCard(
              label: 'Orders',
              value: '${d.today.orders}',
              icon: Icons.receipt_long_outlined,
              accentColor: AppColors.info,
            ),

            StatCard(
              label: 'UDHAR / Credit',
              value: Formatters.currency(d.today.credit),
              icon: Icons.account_balance_wallet_outlined,
              accentColor: AppColors.credit,
            ),

            StatCard(
              label: 'Low Stock',
              value: '${d.lowStockCount} Items',
              icon: Icons.inventory_2_outlined,
              accentColor: AppColors.warning,
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ALERTS
  // ---------------------------------------------------------------------------

  Widget _buildAlerts() {
    final d = _data!;

    final alerts = <Widget>[];

    if (d.lowStockCount > 0) {
      alerts.add(
        _alertTile(
          Icons.warning_amber_rounded,
          AppColors.warning,
          '${d.lowStockCount} products are low on stock',
        ),
      );
    }

    if (d.outstandingCreditTotal > 0) {
      alerts.add(
        _alertTile(
          Icons.account_balance_wallet_outlined,
          AppColors.credit,
          '${Formatters.currency(d.outstandingCreditTotal)} outstanding from ${d.outstandingCreditCustomerCount} customers',
        ),
      );
    }

    if (alerts.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alerts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: 10),
        ...alerts,
      ],
    );
  }

  Widget _alertTile(
    IconData icon,
    Color color,
    String text,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SALES OVERVIEW (from GET /dashboard/sales-overview) -- the other
  // independent section.
  // ---------------------------------------------------------------------------

  Widget _buildSalesOverviewBlock() {
    if (_overview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_overviewError != null) ...[
            InlineRetryBanner(
              message: 'Could not refresh sales overview. Showing last known data.',
              onRetry: _loadOverview,
            ),
            SizedBox(height: 12),
          ],
          _buildSalesOverview(),
        ],
      );
    }

    if (_loadingOverview) {
      return SectionLoadingBox(height: 280);
    }

    return SectionErrorBox(
      message: _overviewError ?? 'Could not load sales overview.',
      onRetry: _loadOverview,
    );
  }

  Widget _buildSalesOverview() {
    final o = _overview!;

    final tabs = {
      'Today': o.today,
      'Yesterday': o.yesterday,
      'This Week': o.thisWeek,
      'This Month': o.thisMonth,
    };

    final selected = tabs[_overviewTab]!;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Sales Overview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),

              SizedBox(width: 10),

              Flexible(
                child: Text(
                  Formatters.currency(selected.sales),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                ),
              ),
            ],
          ),

          SizedBox(height: 10),

          // Tabs
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tabs.keys.map((label) {
              final isSelected = _overviewTab == label;

              return ChoiceChip(
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _overviewTab = label;
                  });
                },
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: AppColors.border,
                  ),
                ),
              );
            }).toList(),
          ),

          SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 160,
            child: o.last14Days.isEmpty
                ? Center(
                    child: Text(
                      'No sales data yet',
                      style: TextStyle(
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: false,
                      ),
                      titlesData: FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: false,
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (
                              int i = 0;
                              i < o.last14Days.length;
                              i++
                            )
                              FlSpot(
                                i.toDouble(),
                                o.last14Days[i].sales,
                              ),
                          ],
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: false,
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          SizedBox(height: 8),

          // Payment summary
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 350;

              if (isSmall) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash ${Formatters.currency(selected.cash)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'UPI ${Formatters.currency(selected.upi)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Credit ${Formatters.currency(selected.credit)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              }

              return Text(
                'Cash ${Formatters.currency(selected.cash)}   ·   '
                'UPI ${Formatters.currency(selected.upi)}   ·   '
                'Credit ${Formatters.currency(selected.credit)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECENT ORDERS + TOP PRODUCTS (also from GET /dashboard, so they share
  // the stats section's loading/error state).
  // ---------------------------------------------------------------------------

  Widget _buildOrdersAndProductsBlock() {
    if (_data != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentOrders(),
          SizedBox(height: 20),
          _buildTopProducts(),
        ],
      );
    }

    if (_loadingStats) {
      return SectionLoadingBox(height: 180);
    }

    // Already surfaced via _buildStatsBlock()'s error box above; avoid
    // showing the same error twice.
    return SizedBox.shrink();
  }

  Widget _buildRecentOrders() {
    final orders = _data!.recentOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Orders',
          style: Theme.of(context).textTheme.titleMedium,
        ),

        SizedBox(height: 10),

        if (orders.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No orders yet today.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          ...orders.map(
            (o) => _recentOrderTile(o),
          ),
      ],
    );
  }

  Widget _recentOrderTile(RecentOrderSummary o) {
    // Status is the single source of truth. A completed order can never be
    // rendered as NEW/PENDING, regardless of whether it came from QR or POS.
    final status = o.status.trim().toLowerCase();
    final statusLabel = switch (status) {
      'open' => 'NEW',
      'preparing' => 'PREPARING',
      'ready' => 'READY',
      'completed' => 'COMPLETED',
      'voided' => 'VOIDED',
      _ => status.isEmpty ? 'UNKNOWN' : status.toUpperCase(),
    };

    final statusColor = switch (status) {
      'open' => AppColors.warning,
      'preparing' => AppColors.info,
      'ready' => AppColors.primary,
      'completed' => AppColors.success,
      'voided' => AppColors.textMuted,
      _ => AppColors.textSecondary,
    };

    final payment = o.paymentMethod.trim().isEmpty
        ? (status == 'completed' ? '—' : 'UNPAID')
        : o.paymentMethod.toUpperCase();

    final paymentColor = switch (payment) {
      'CASH' => AppColors.cash,
      'UPI' => AppColors.upi,
      'CREDIT' => AppColors.credit,
      'MIXED' => AppColors.accent,
      _ => AppColors.textSecondary,
    };

    return InkWell(
      onTap: () => _openOrder(o.orderNumber),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${o.orderNumber}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    o.itemsSummary.isEmpty ? 'Order' : o.itemsSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      if (o.orderSource == 'qr') ...[
                        Icon(Icons.qr_code_2_outlined, size: 13, color: AppColors.textMuted),
                        SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          [
                            if (o.orderSource == 'qr') 'QR${o.tableName != null ? ' • ${o.tableName}' : ''}',
                            Formatters.relative(o.createdAt),
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(o.grandTotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      _orderStatusChip(statusLabel, statusColor),
                      if (payment != '—')
                        _orderStatusChip(payment, paymentColor),
                    ],
                  ),
                  if (status == 'open') ...[
                    SizedBox(height: 3),
                    Text(
                      'Awaiting confirmation',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderStatusChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OPEN ORDER
  // ---------------------------------------------------------------------------

  Future<void> _openOrder(int orderNumber) async {
    try {
      final orders = await OrderService().list(
        search: orderNumber.toString(),
      );

      if (orders.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: orders.first.id,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order not found.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open order. Please try again.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TOP PRODUCTS
  // ---------------------------------------------------------------------------

  Widget _buildTopProducts() {
    final products = _data!.topSellingProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Selling Products',
          style: Theme.of(context).textTheme.titleMedium,
        ),

        SizedBox(height: 10),

        if (products.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No sales data yet.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Column(
              children: products.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      SizedBox(width: 8),

                      Flexible(
                        child: Text(
                          '${p.quantitySold} sold',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
