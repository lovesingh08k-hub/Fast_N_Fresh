import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/pos_ui.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';
import '../tables/table_detail_screen.dart';
import '../tables/qr_management_screen.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';

import '../pos/counter_slots_screen.dart';
import 'open_bill.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with WidgetsBindingObserver {
  final _service = OrderService();
  final _tableService = TableService();
  final GlobalKey<CountersPanelState> _takeawayKey = GlobalKey<CountersPanelState>();
  final GlobalKey<CountersPanelState> _deliveryKey = GlobalKey<CountersPanelState>();

  List<Order>? _orders;
  List<CafeTable> _tables = [];
  String _channelTab = 'All';

  /// 'progress' (being prepared), 'payment' (served, not yet paid) or 'tables'.
  String _view = 'progress';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  bool _isRefreshing = true;
  String? _error;

  Timer? _qrPollTimer;

  /*
   * Only today's NEW QR orders are tracked here.
   */
  final Set<String> _knownQrOrderIds = {};

  bool _hasSeededQrOrders = false;

  AppLifecycleState? _lastLifecycleState;

  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _load();

    /*
     * Poll every 8 seconds so QR orders appear quickly.
     */
    _qrPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) {
        if (mounted) {
          _load(notifyNewQr: true);
        }
      },
    );
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _connectivity?.removeListener(_handleConnectivityChange);

    _qrPollTimer?.cancel();
    _searchController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground =
        state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && _error != null && mounted) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && _error != null) {
      _load();
    }

    _wasOnline = isOnline;
  }

  /*
   * Returns true only when the order was created today.
   *
   * This is intentionally used only for NEW QR / kitchen queue logic.
   */
  bool _isCreatedToday(Order order) {
    final now = DateTime.now();
    final created = order.createdAt.toLocal();

    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  /*
   * A NEW QR order means:
   *
   * - QR order
   * - open
   * - unattended
   * - created today
   */
  bool _isNewQrOrder(Order order) {
    return order.isQrOrder &&
        order.status == 'open' &&
        order.staffName == null &&
        _isCreatedToday(order);
  }

  /*
   * Shows an app-wide popup for newly arrived QR orders.
   */
  void _showNewOrderPopup(List<Order> newOrders) {
    final navState = PwpPosApp.navigatorKey.currentState;
    final popupContext = navState?.overlay?.context;

    if (popupContext == null) return;

    showDialog(
      context: popupContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            newOrders.length == 1
                ? 'New Order Received'
                : '${newOrders.length} New Orders Received',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: newOrders.take(5).map((order) {
                final itemsSummary = order.items
                    .map(
                      (item) => '${item.quantity}× ${item.name}',
                    )
                    .join(', ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.orderNumber}'
                        '${order.tableName != null ? ' · ${order.tableName}' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        itemsSummary,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                if (newOrders.length == 1) {
                  navState?.push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(
                        orderId: newOrders.first.id,
                      ),
                    ),
                  );
                } else if (newOrders.isNotEmpty) {
                  // Kitchen Display was removed. Open the first order in the
                  // normal Orders flow; the operator can process all orders
                  // without leaving this section.
                  navState?.push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(
                        orderId: newOrders.first.id,
                      ),
                    ),
                  );
                }

                if (mounted) {
                  _load();
                }
              },
              child: const Text('View'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _load({
    bool notifyNewQr = false,
  }) async {
    if (!mounted) return;

    setState(() {
      _isRefreshing = true;
    });

    /*
     * Kitchen badge is independent from Orders filters.
     */

    try {
      // Takeaway/Delivery counters reload alongside the tables.
      _takeawayKey.currentState?.refresh(silent: true);
      _deliveryKey.currentState?.refresh(silent: true);

      // The table grid needs every unbilled order, however old, so a tab
      // opened before midnight (or past the first page) is never dropped.
      // Each unbilled status is fetched exactly (no date filter), which every
      // backend version supports.
      final results = await Future.wait([
        _service.list(status: 'open', limit: 200),
        _service.list(status: 'preparing', limit: 200),
        _service.list(status: 'ready', limit: 200),
        _tableService.list(),
      ]);
      final orders = [
        ...results[0] as List<Order>,
        ...results[1] as List<Order>,
        ...results[2] as List<Order>,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final tables = results[3] as List<CafeTable>;

      if (!mounted) return;

      /*
       * Only TODAY'S actual NEW QR orders participate in
       * notification / popup detection.
       */
      final currentQrOrders = orders.where(
        (order) => _isNewQrOrder(order),
      );

      final currentQrIds = currentQrOrders.map((order) => order.id).toSet();

      final newQrOrderIds = _hasSeededQrOrders
          ? currentQrIds.difference(_knownQrOrderIds)
          : <String>{};

      /*
       * Update known IDs.
       */
      _knownQrOrderIds
        ..clear()
        ..addAll(currentQrIds);

      _hasSeededQrOrders = true;

      setState(() {
        _orders = orders;
        _tables = tables;
        _error = null;
      });

      /*
       * Notify only genuinely new TODAY QR orders.
       */
      if (notifyNewQr && newQrOrderIds.isNotEmpty && mounted) {
        SystemSound.play(
          SystemSoundType.alert,
        );

        final newOrders = currentQrOrders
            .where(
              (order) => newQrOrderIds.contains(order.id),
            )
            .toList();

        if (newOrders.isNotEmpty) {
          _showNewOrderPopup(newOrders);

          final notificationBody = newOrders.length == 1
              ? '#${newOrders.first.orderNumber} • '
                  '${newOrders.first.items.map(
                        (item) => '${item.quantity}x ${item.name}',
                      ).join(', ')}'
              : '${newOrders.length} new QR orders are '
                  'waiting for confirmation.';

          NotificationService.instance.showNewOrderNotification(
            count: newOrders.length,
            bodyOverride: notificationBody,
          );
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      /*
       * Keep previous successful data on screen.
       */
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load orders.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildTableOrdersBody(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        FreshHeader(
          title: 'Orders',
          subtitle: 'Tables and running orders',
          actions: [
            FreshHeaderAction(
              tooltip: _showSearch ? 'Close Search' : 'Search',
              icon: _showSearch ? Icons.close_rounded : Icons.search_rounded,
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) _searchController.clear();
                });
              },
            ),
            FreshHeaderAction(
              tooltip: 'QR Management',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrManagementScreen()),
                );
                if (mounted) _load();
              },
            ),
          ],
        ),
        if (_showSearch) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search table or order...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: FreshUi.mint.withValues(alpha: .3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: FreshUi.mint.withValues(alpha: .3)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _tabColor(String tab) {
    switch (tab) {
      case 'Occupied':
        return FreshUi.red;
      case 'Billing':
        return FreshUi.amber;
      default:
        return tab == 'Available' ? FreshUi.green : FreshUi.mint;
    }
  }

  Widget _tabPill(String tab) {
    final selected = _channelTab == tab;
    final color = _tabColor(tab);
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _channelTab = tab),
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? FreshUi.mint : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? FreshUi.mint : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tab, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(width: 6),
                Text('${_countFor(tab)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableOrdersBody() {
    final query = _searchController.text.trim().toLowerCase();
    final tables = _tables.where((table) {
      if (query.isNotEmpty && !table.name.toLowerCase().contains(query)) {
        return false;
      }
      switch (_channelTab) {
        case 'Occupied':
          return table.isOccupied;
        case 'Available':
          return table.isAvailable;
        case 'Billing':
          return table.isOccupied &&
              _tableOrder(table)?.paymentStatus == 'pending';
        default:
          return true;
      }
    }).toList();

    if (_orders == null && _isRefreshing) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 160),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_orders == null && _error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 16),
          const Center(
              child: Text('Could not load orders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Center(
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted))),
          const SizedBox(height: 20),
          Center(
              child: ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'))),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        _viewSwitcher(),
        const SizedBox(height: 14),
        if (_view != 'tables')
          ..._runningList()
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Row(
              children: [
                const Icon(Icons.table_restaurant_outlined,
                    color: FreshUi.mint, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${_countFor('Occupied')}',
                          style: const TextStyle(
                              color: FreshUi.amber, fontWeight: FontWeight.w800)),
                      const TextSpan(text: ' occupied  •  '),
                      TextSpan(
                          text: '${_countFor('Available')}',
                          style: const TextStyle(
                              color: FreshUi.green, fontWeight: FontWeight.w800)),
                      const TextSpan(text: ' available'),
                    ]),
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                if (_isRefreshing)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Occupied', 'Available', 'Billing']
                  .map(_tabPill)
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InlineRetryBanner(
                  message: 'Could not refresh. Showing the last loaded data.',
                  onRetry: _load),
            ),
          if (tables.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: Text(
                  query.isEmpty
                      ? 'No tables found.'
                      : 'No matching tables found.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tables.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 206,
                  ),
                  itemBuilder: (_, index) => _OrderTableCard(
                    table: tables[index],
                    order: _tableOrder(tables[index]),
                    canManageQr: context
                            .read<AuthProvider>()
                            .currentUser
                            ?.canManageTables ??
                        false,
                    onOpen: () => _openOrderTable(tables[index]),
                    onQr: () => _openTableQr(tables[index]),
                  ),
                );
              },
            ),
          const SizedBox(height: 18),
          CountersPanel(key: _takeawayKey, orderType: 'takeaway'),
          const SizedBox(height: 18),
          CountersPanel(key: _deliveryKey, orderType: 'delivery'),
        ],
      ],
    );
  }

  /// Unbilled orders split into "being prepared" and "waiting for payment".
  bool _isInProgress(Order order) {
    if (order.isQrOrder) return order.status == 'open' || order.status == 'preparing';
    return order.kots.any((k) => k.status == 'new' || k.status == 'preparing');
  }

  List<Order> get _running {
    final query = _searchController.text.trim().toLowerCase();
    return (_orders ?? const <Order>[])
        .where((o) => o.status != 'completed' && o.status != 'voided' && o.paymentStatus != 'paid')
        .where((o) => _view == 'progress' ? _isInProgress(o) : !_isInProgress(o))
        .where((o) =>
            query.isEmpty ||
            (o.printCustomerName ?? '').toLowerCase().contains(query) ||
            (o.tableName ?? '').toLowerCase().contains(query) ||
            '${o.orderNumber}'.contains(query))
        .toList();
  }

  int _runningCount(bool inProgress) => (_orders ?? const <Order>[])
      .where((o) => o.status != 'completed' && o.status != 'voided' && o.paymentStatus != 'paid')
      .where((o) => _isInProgress(o) == inProgress)
      .length;

  Widget _viewSwitcher() {
    final views = [
      ('progress', 'In Progress', _runningCount(true)),
      ('payment', 'Waiting Payment', _runningCount(false)),
      ('tables', 'Tables', null),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          for (final v in views)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _view = v.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _view == v.$1 ? AppColors.primaryLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      v.$3 == null ? v.$2 : '${v.$2} (${v.$3})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _view == v.$1 ? FontWeight.w800 : FontWeight.w600,
                        color: _view == v.$1 ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Short code for the badge: table number, counter (T1/D2) or bill no.
  String _codeFor(Order o) {
    final label = o.tableCustomerLabel?.trim() ?? '';
    final slot = RegExp(r'^([TD]\d+)').firstMatch(label);
    if (o.orderType != 'dine_in' && slot != null) return slot.group(1)!;
    if (o.tableNumber != null) return 'T${o.tableNumber}';
    final name = o.tableName?.trim() ?? '';
    final digits = RegExp(r'\d+').firstMatch(name)?.group(0);
    if (name.isNotEmpty) return '${name[0].toUpperCase()}${digits ?? ''}';
    return '#${o.orderNumber}';
  }

  List<Widget> _runningList() {
    final orders = _running;
    if (orders.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: FreshUi.card(),
          child: Column(
            children: [
              Text(_view == 'progress' ? '👨‍🍳' : '🧾', style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                _view == 'progress' ? 'Nothing cooking right now' : 'No bills waiting for payment',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text('Orders sent to the kitchen show up here.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ],
          ),
        ),
      ];
    }
    return [
      for (final o in orders)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                await openBill(context, o);
                if (mounted) _load();
              },
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: FreshUi.card(),
                child: Row(
                  children: [
                    CodeBadge(code: _codeFor(o), color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.printCustomerName ?? (o.tableName ?? 'Bill #${o.orderNumber}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${o.items.fold<int>(0, (n, i) => n + i.quantity)} items · ${o.orderType == 'dine_in' ? 'Dine-in' : o.orderType == 'delivery' ? 'Delivery' : 'Takeaway'} · #${o.orderNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _isInProgress(o)
                            ? StatusPill(label: 'In Progress', color: AppColors.warning, icon: Icons.timelapse_rounded)
                            : StatusPill(label: 'Ready', color: AppColors.success, icon: Icons.done_all_rounded),
                        const SizedBox(height: 6),
                        Text(
                          _isInProgress(o) ? 'Cooking now' : 'Collect ${Formatters.currency(o.grandTotal)}',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  int _countFor(String tab) {
    switch (tab) {
      case 'Occupied':
        return _tables.where((t) => t.isOccupied).length;
      case 'Available':
        return _tables.where((t) => t.isAvailable).length;
      case 'Billing':
        return _tables
            .where((t) =>
                t.isOccupied && _tableOrder(t)?.paymentStatus == 'pending')
            .length;
      default:
        return _tables.length;
    }
  }

  Order? _tableOrder(CafeTable table) {
    final orders = _orders ?? const <Order>[];
    for (final order in orders) {
      if (order.tableId == table.id &&
          order.status != 'completed' &&
          order.status != 'voided') {
        return order;
      }
    }
    return null;
  }

  Future<void> _openOrderTable(CafeTable table) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TableDetailScreen(tableId: table.id)),
    );
    if (mounted) _load();
  }

  Future<void> _openTableQr(CafeTable table) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => QrManagementScreen(focusTableId: table.id)),
    );
    if (mounted) _load();
  }
}

class _OrderTableCard extends StatelessWidget {
  final CafeTable table;
  final Order? order;
  final bool canManageQr;
  final VoidCallback onOpen;
  final VoidCallback onQr;

  const _OrderTableCard({
    required this.table,
    required this.order,
    required this.canManageQr,
    required this.onOpen,
    required this.onQr,
  });

  bool get _isBilling =>
      order != null &&
      order!.paymentStatus == 'pending' &&
      (order!.status == 'ready' || order!.status == 'preparing');

  String get _status {
    if (_isBilling) return 'Billing';
    if (table.isOccupied) return 'Occupied';
    if (table.isReserved) return 'Reserved';
    return 'Available';
  }

  Color _statusColor(BuildContext context) {
    switch (_status) {
      case 'Occupied':
        return FreshUi.red;
      case 'Billing':
        return FreshUi.amber;
      case 'Reserved':
        return FreshUi.amber;
      default:
        return FreshUi.green;
    }
  }

  String _ageText() {
    final at = table.latestOpenOrderAt;
    if (at == null) return '';
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '$minutes mins';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'}';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    final itemPreview = order?.items.take(3).toList() ?? const <OrderItem>[];
    final itemCount =
        order?.items.fold<int>(0, (sum, item) => sum + item.quantity) ?? 0;
    final age = _ageText();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: FreshUi.card(tint: statusColor, tintStrength: .05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statusPill(statusColor),
                        const SizedBox(height: 4),
                        Text(
                          table.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _qrButton(),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _meta(
                    Icons.groups_outlined,
                    order != null ? '$itemCount Items' : '${table.capacity} Seats',
                  ),
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: AppColors.border,
                  ),
                  Expanded(
                    child: order != null
                        ? (age.isEmpty
                            ? const SizedBox.shrink()
                            : _meta(Icons.schedule_rounded, age))
                        : _meta(Icons.chair_outlined,
                            table.isReserved ? 'Reserved' : 'Ready for guests'),
                  ),
                ],
              ),
              Expanded(
                child: order == null
                    ? Center(
                        child: Icon(Icons.table_restaurant_outlined,
                            size: 32, color: statusColor.withValues(alpha: .7)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(
                              height: 12,
                              color: AppColors.border.withValues(alpha: .8)),
                          ...itemPreview.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.restaurant_rounded,
                                        size: 13,
                                        color: AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 12))),
                                    Text('×${item.quantity}',
                                        style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12)),
                                  ],
                                ),
                              )),
                          if (order!.items.length > 3)
                            Text('+${order!.items.length - 3} more items',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              FreshGradientButton(
                onPressed: onOpen,
                height: 34,
                gradient: table.isOccupied || order != null
                    ? (_isBilling
                        ? FreshUi.amberGradient
                        : FreshUi.redGradient)
                    : FreshUi.greenGradient,
                icon: order != null
                    ? Icons.visibility_outlined
                    : table.isOccupied
                        ? Icons.table_restaurant_outlined
                        : Icons.add_circle_outline_rounded,
                label: order != null
                    ? 'View Order'
                    : table.isOccupied
                        ? 'Open Table'
                        : 'Start Order',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _status,
            style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _qrButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canManageQr || table.hasQrNumber ? onQr : onOpen,
        borderRadius: BorderRadius.circular(9),
        child: Tooltip(
          message: table.hasQrNumber ? 'View QR' : 'Set up QR',
          child: Ink(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(Icons.qr_code_2_rounded,
                color: AppColors.textSecondary, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}
