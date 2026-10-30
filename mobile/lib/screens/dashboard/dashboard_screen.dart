import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_config.dart';
import '../../core/widgets/archive_due_banner.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/pos_ui.dart';
import '../orders/bill_history_screen.dart';
import 'home_widgets.dart';
import 'notifications_sheet.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/dashboard_models.dart';
import '../../services/dashboard_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../orders/open_bill.dart';
import '../../services/order_service.dart';

import '../../core/widgets/theme_reveal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
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
    // Popular Dishes shows menu photos and prices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CatalogProvider>().ensureLoaded();
    });
    // QR orders are created outside the staff app, so the dashboard must
    // refresh periodically instead of waiting for the user to revisit the
    // tab. This keeps the Orders card and Recent Orders live.
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
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

    final returnedToForeground =
        state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground &&
        mounted &&
        (_statsError != null || _overviewError != null)) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline &&
        !_wasOnline &&
        (_statsError != null || _overviewError != null)) {
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


  @override
  Widget build(BuildContext context) {
    final userName = context.watch<AuthProvider>().currentUser?.name ?? 'Admin';


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
      body = const LoadingState();
    } else if (nothingLoadedYet && everythingFailed) {
      body = ErrorState(
        message:
            _statsError ?? _overviewError ?? 'Could not load the dashboard.',
        onRetry: _load,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24,
          ),
          children: [
            HomeGreeting(userName: userName),
            const ArchiveDueBanner(),
            const SizedBox(height: 16),
            if (_data != null) ...[
              TodaySalesCard(today: _data!.today, yesterdaySales: _overview?.yesterday.sales),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MiniStatCard(
                      icon: Icons.local_fire_department_rounded,
                      color: AppColors.primary,
                      label: 'Running orders',
                      value: '${_data!.runningOrders}',
                      note: _data!.runningOrders == 0
                          ? 'No open bills'
                          : '${Formatters.currency(_data!.runningValue)} unbilled',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MiniStatCard(
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.credit,
                      label: 'Udhar due',
                      value: Formatters.currency(_data!.outstandingCreditTotal),
                      note: '${_data!.outstandingCreditCustomerCount} customer${_data!.outstandingCreditCustomerCount == 1 ? '' : 's'}',
                    ),
                  ),
                ],
              ),
              if (_data!.lowStockCount > 0) ...[
                const SizedBox(height: 12),
                _lowStockBanner(_data!.lowStockCount),
              ],
            ] else if (_statsError != null)
              InlineRetryBanner(message: _statsError!, onRetry: _loadStats),
            const SizedBox(height: 16),
            QuickActions(
              onOrders: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BillHistoryScreen()),
              ),
            ),
            const SizedBox(height: 22),
            const SectionTitle('Popular Dishes'),
            PopularDishes(products: _data?.topSellingProducts ?? const []),
            const SizedBox(height: 22),
            _buildSalesOverviewBlock(),
            const SizedBox(height: 20),
            _buildOrdersAndProductsBlock(),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: HomeHeader(
                actions: [
                  Builder(builder: (context) {
                    final notices = _data == null ? const <HomeNotice>[] : HomeNotice.fromDashboard(context, _data!);
                    final unread = notices.where((n) => n.unread).length;
                    return HeaderCircleButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      onTap: () => showNotificationsSheet(context, notices),
                      child: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.notifications_none_rounded, size: 21, color: AppColors.textPrimary),
                      ),
                    );
                  }),
                  Consumer<ThemeProvider>(
                    builder: (context, theme, _) => HeaderCircleButton(
                      icon: theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      tooltip: theme.isDark ? 'Switch to light mode' : 'Switch to dark mode',
                      onTap: () => changeThemeWithReveal(
                        context,
                        theme.isDark ? AppThemeMode.light : AppThemeMode.dark,
                        originContext: context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _lowStockBanner(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count item${count == 1 ? ' is' : 's are'} running low on stock',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
              message:
                  'Could not refresh sales overview. Showing last known data.',
              onRetry: _loadOverview,
            ),
            const SizedBox(height: 12),
          ],
          _buildSalesOverview(),
        ],
      );
    }

    if (_loadingOverview) {
      return const SectionLoadingBox(height: 280);
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
      'Week': o.thisWeek,
      'Month': o.thisMonth,
    };

    final selected = tabs[_overviewTab]!;
    final days = o.last14Days;
    final maxSales = days.fold<double>(0, (m, d) => d.sales > m ? d.sales : m);
    final interval = _niceInterval(maxSales);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: FreshUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconTile(Icons.bar_chart_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales Overview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    Text(
                      'Total sales for selected period',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(selected.sales),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: FreshUi.mint),
                  ),
                  Text('Total Sales',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Tabs: four equal pills that always fit on one row.
          Row(
            children: [
              for (final label in tabs.keys) ...[
                if (label != tabs.keys.first) const SizedBox(width: 6),
                Expanded(child: _periodPill(label)),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Chart
          SizedBox(
            height: 160,
            child: days.isEmpty
                ? Center(
                    child: Text(
                      'No sales data yet',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: interval * 4,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: interval,
                            getTitlesWidget: (value, meta) => Text(
                              _compactAmount(value),
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              final last = days.length - 1;
                              // Label only the first, middle and last day.
                              if (i != 0 && i != last && i != last ~/ 2) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _dayLabel(days[i].date),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          left: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < days.length; i++)
                              FlSpot(i.toDouble(), days[i].sales),
                          ],
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: FreshUi.mint,
                          barWidth: 2.5,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, bar) =>
                                spot.x == 0 || spot.x == days.length - 1,
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 3.5,
                              color: FreshUi.mint,
                              strokeWidth: 2,
                              strokeColor: AppColors.surface,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                FreshUi.mint.withValues(alpha: .28),
                                FreshUi.mint.withValues(alpha: .0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 4),
          Text(
            'Last 14 days',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),

          // Payment summary
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _paymentChip('Cash', selected.cash, AppColors.cash),
              _paymentChip('UPI', selected.upi, AppColors.upi),
              _paymentChip('Credit', selected.credit, AppColors.credit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconTile(IconData icon) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: FreshUi.mint.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: FreshUi.mint, size: 17),
    );
  }

  Widget _periodPill(String label) {
    final isSelected = _overviewTab == label;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _overviewTab = label),
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          height: 32,
          decoration: BoxDecoration(
            color: isSelected ? FreshUi.mint : null,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: isSelected ? Colors.transparent : AppColors.border),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label ${Formatters.currency(amount)}',
        style: TextStyle(
            color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// A round y-axis step so four grid lines cover [max].
  double _niceInterval(double max) {
    if (max <= 0) return 25;
    final raw = max / 4;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    for (final step in [1, 2, 2.5, 5, 10]) {
      final candidate = step * magnitude;
      if (candidate >= raw) return candidate.toDouble();
    }
    return (10 * magnitude).toDouble();
  }

  String _compactAmount(double value) {
    if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(value % 100000 == 0 ? 0 : 1)}L';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  String _dayLabel(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null ? date : Formatters.shortDate(parsed);
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
          const SizedBox(height: 20),
          _buildTopProducts(),
        ],
      );
    }

    if (_loadingStats) {
      return const SectionLoadingBox(height: 180);
    }

    // Already surfaced via _buildStatsBlock()'s error box above; avoid
    // showing the same error twice.
    return const SizedBox.shrink();
  }

  Widget _buildRecentOrders() {
    final orders = _data!.recentOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.receipt_long_rounded, 'Recent Orders'),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No orders yet today.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          )
        else
          ...orders.map(_recentOrderTile),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        _iconTile(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
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
      'open' => FreshUi.amber,
      'preparing' => AppColors.info,
      'ready' => FreshUi.mint,
      'completed' => FreshUi.mint,
      'voided' => AppColors.textMuted,
      _ => AppColors.textSecondary,
    };

    final payment = o.paymentMethod.trim().isEmpty
        ? (status == 'completed' ? '—' : 'PENDING')
        : o.paymentMethod.toUpperCase();

    final paymentColor = switch (payment) {
      'CASH' => FreshUi.mint,
      'UPI' => AppColors.upi,
      'CREDIT' => AppColors.credit,
      'MIXED' => AppColors.accent,
      _ => AppColors.textSecondary,
    };

    final firstItem = _firstItemName(o.itemsSummary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openOrder(o.orderNumber),
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _thumbnail(firstItem, 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${o.orderNumber}',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            Formatters.currency(o.grandTotal),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        o.itemsSummary.isEmpty ? 'Order' : o.itemsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                              o.orderSource == 'qr'
                                  ? Icons.qr_code_2_rounded
                                  : Icons.schedule_rounded,
                              size: 13,
                              color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [
                                if (o.orderSource == 'qr')
                                  'QR${o.tableName != null ? ' • ${o.tableName}' : ''}',
                                Formatters.relative(o.createdAt),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _orderStatusChip(statusLabel, statusColor),
                          if (payment != '—') ...[
                            const SizedBox(width: 6),
                            _orderStatusChip(payment, paymentColor),
                          ],
                        ],
                      ),
                      if (status == 'open') ...[
                        const SizedBox(height: 4),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(Icons.circle, size: 6, color: FreshUi.amber),
                            SizedBox(width: 5),
                            Text(
                              'Awaiting confirmation',
                              style: TextStyle(
                                color: FreshUi.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// "2 Masala Dosa, 1 Hot Tea" -> "Masala Dosa".
  String _firstItemName(String summary) {
    final first = summary.split(',').first.trim();
    return first.replaceFirst(RegExp(r'^\d+\s*[x×]?\s*'), '');
  }

  /// Uploaded product photo when the catalog has one, otherwise an icon that
  /// matches the kind of item. Photos are only used on this dashboard.
  Widget _thumbnail(String itemName, double size) {
    final key = itemName.trim().toLowerCase();
    String imageUrl = '';
    for (final p in context.read<CatalogProvider>().products) {
      if (p.name.trim().toLowerCase() == key) {
        imageUrl = p.imageUrl;
        break;
      }
    }

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .25),
        color: FreshUi.mint.withValues(alpha: .1),
      ),
      child: Icon(_foodIcon(key), color: FreshUi.mint, size: size * .5),
    );

    if (imageUrl.trim().isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .25),
      child: Image.network(
        ApiConfig.resolveAssetUrl(imageUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  IconData _foodIcon(String name) {
    bool has(List<String> words) => words.any(name.contains);
    if (has(['pizza'])) return Icons.local_pizza_rounded;
    if (has(['burger'])) return Icons.lunch_dining_rounded;
    if (has(['ice cream', 'ice-cream', 'brownie', 'cake'])) {
      return Icons.icecream_rounded;
    }
    if (has(['coffee', 'tea', 'chocolate'])) return Icons.local_cafe_rounded;
    if (has(['shake', 'mocktail', 'mojito', 'lassi', 'lagoon'])) {
      return Icons.local_drink_rounded;
    }
    if (has([
      'noodle',
      'chowmein',
      'chowmin',
      'maggie',
      'pasta',
      'rice',
      'biryani',
      'soup'
    ])) {
      return Icons.ramen_dining_rounded;
    }
    if (has(['dosa', 'paratha', 'idli', 'vada', 'uttapam', 'wrap', 'roll'])) {
      return Icons.breakfast_dining_rounded;
    }
    if (has(['fries', 'momos', 'nugget', 'finger'])) {
      return Icons.fastfood_rounded;
    }
    return Icons.restaurant_rounded;
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
        openBill(context, orders.first);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order not found.')),
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
          const SnackBar(
              content: Text('Unable to open order. Please try again.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TOP PRODUCTS
  // ---------------------------------------------------------------------------

  Widget _buildTopProducts() {
    final products = _data!.topSellingProducts;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: FreshUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.bar_chart_rounded, 'Top Selling Products'),
          const SizedBox(height: 4),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No sales data yet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < products.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        indent: 0,
                        endIndent: 0,
                        color: AppColors.border),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceElevated,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _thumbnail(products[i].name, 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            products[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${products[i].quantitySold} sold',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
