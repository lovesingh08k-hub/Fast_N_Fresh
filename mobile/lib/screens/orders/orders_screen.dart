import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../models/order.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';
import '../tables/table_detail_screen.dart';
import '../tables/qr_management_screen.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';

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

  List<Order>? _orders;
  List<CafeTable> _tables = [];
  String _channelTab = 'All';
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

  String _filterRange = 'Today';
  String? _filterPayment;
  String? _filterOrderType;

  /*
   * Only used when _filterRange == 'Custom'. Selected via a date-range
   * picker inside the filter sheet.
   */
  DateTime? _customFrom;
  DateTime? _customTo;

  static const List<String> _dateRangeOptions = [
    'Today',
    'Yesterday',
    'This Week',
    'This Month',
    'Custom',
    'All',
  ];

  /*
   * Existing payment methods supported by the backend (Order.paymentMethod
   * enum: CASH | UPI | CREDIT | MIXED). Kept in one place so the filter
   * sheet always reflects every payment type the app actually supports,
   * instead of a hand-picked subset.
   */
  static const List<String> _paymentMethodOptions = [
    'CASH',
    'UPI',
    'CREDIT',
    'MIXED',
  ];

  static const List<String> _orderTypeOptions = [
    'dine_in',
    'takeaway',
    'delivery',
  ];

  /// Inclusive local date range used by the Orders history API.
  ///
  /// The backend accepts ISO timestamps and compares createdAt with $gte/$lte,
  /// so date filters are expanded to the full local day rather than sending
  /// midnight for both ends.
  DateTime? get _fromDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_filterRange) {
      case 'Today':
        return today;
      case 'Yesterday':
        return today.subtract(const Duration(days: 1));
      case 'This Week':
        final daysFromMonday = today.weekday - DateTime.monday;
        return today.subtract(Duration(days: daysFromMonday));
      case 'This Month':
        return DateTime(today.year, today.month, 1);
      case 'Custom':
        return _customFrom == null
            ? today
            : DateTime(
                _customFrom!.year,
                _customFrom!.month,
                _customFrom!.day,
              );
      case 'All':
        return null;
      default:
        return today;
    }
  }

  DateTime? get _toDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime endOfDay(DateTime date) => DateTime(
          date.year,
          date.month,
          date.day,
          23,
          59,
          59,
          999,
        );

    switch (_filterRange) {
      case 'Today':
        return endOfDay(today);
      case 'Yesterday':
        return endOfDay(today.subtract(const Duration(days: 1)));
      case 'This Week':
        final daysFromMonday = today.weekday - DateTime.monday;
        final monday = today.subtract(Duration(days: daysFromMonday));
        return endOfDay(monday.add(const Duration(days: 6)));
      case 'This Month':
        final firstOfNextMonth = today.month == 12
            ? DateTime(today.year + 1, 1, 1)
            : DateTime(today.year, today.month + 1, 1);
        return endOfDay(firstOfNextMonth.subtract(const Duration(days: 1)));
      case 'Custom':
        return _customTo == null ? endOfDay(today) : endOfDay(_customTo!);
      case 'All':
        return null;
      default:
        return endOfDay(today);
    }
  }

  String _orderTypeLabel(String type) {
    switch (type) {
      case 'dine_in':
        return 'Dine-In';
      case 'takeaway':
        return 'Takeaway';
      case 'delivery':
        return 'Delivery';
      default:
        return type;
    }
  }

  String get _dateRangeSummary {
    if (_filterRange == 'Custom' &&
        _customFrom != null &&
        _customTo != null) {
      return '${Formatters.shortDate(_customFrom!)} – '
          '${Formatters.shortDate(_customTo!)}';
    }

    return _filterRange;
  }

  int get _activeFilterCount {
    var count = 0;

    if (_filterRange != 'Today') count++;
    if (_filterPayment != null) count++;
    if (_filterOrderType != null) count++;

    return count;
  }

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
    final wasBackgrounded =
        _lastLifecycleState == AppLifecycleState.paused ||
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
    final navState = FastNFreshApp.navigatorKey.currentState;
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
      final results = await Future.wait([
        _service.list(
          from: _fromDate,
          to: _toDate,
          paymentMethod: _filterPayment,
          orderType: _filterOrderType,
        ),
        _tableService.list(),
      ]);
      final orders = results[0] as List<Order>;
      final tables = results[1] as List<CafeTable>;

      if (!mounted) return;

      /*
       * Only TODAY'S actual NEW QR orders participate in
       * notification / popup detection.
       */
      final currentQrOrders = orders.where(
        (order) => _isNewQrOrder(order),
      );

      final currentQrIds = currentQrOrders
          .map((order) => order.id)
          .toSet();

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
      if (notifyNewQr &&
          newQrOrderIds.isNotEmpty &&
          mounted) {
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

          final notificationBody =
              newOrders.length == 1
                  ? '#${newOrders.first.orderNumber} • '
                      '${newOrders.first.items.map(
                        (item) =>
                            '${item.quantity}x ${item.name}',
                      ).join(', ')}'
                  : '${newOrders.length} new QR orders are '
                      'waiting for confirmation.';

          NotificationService.instance
              .showNewOrderNotification(
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 18,
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search table or order...',
                  border: InputBorder.none,
                ),
              )
            : const Text('Orders'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Close Search' : 'Search',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchController.clear();
              });
            },
          ),
          IconButton(
            tooltip: 'QR Management',
            icon: const Icon(Icons.qr_code_2_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => QrManagementScreen()),
              );
              _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildTableOrdersBody(),
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
        case 'Dine In':
          return true;
        case 'Occupied':
          return table.isOccupied;
        case 'Available':
          return table.isAvailable;
        case 'Billing':
          return table.isOccupied && _tableOrder(table)?.paymentStatus == 'pending';
        default:
          return true;
      }
    }).toList();

    if (_orders == null && _isRefreshing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders == null && _error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 16),
          const Center(child: Text('Could not load orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))),
          const SizedBox(height: 20),
          Center(child: ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try Again'))),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: Row(
            children: [
              Icon(Icons.table_restaurant_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Orders', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    Text('Manage all tables and active orders', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (_isRefreshing)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Dine In', 'Occupied', 'Available', 'Billing'].map((tab) {
              final selected = _channelTab == tab;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(tab),
                  selected: selected,
                  onSelected: (_) => setState(() => _channelTab = tab),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InlineRetryBanner(message: 'Could not refresh. Showing the last loaded data.', onRetry: _load),
          ),
        if (tables.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Center(
              child: Text(
                query.isEmpty ? 'No tables found.' : 'No matching tables found.',
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
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 205,
                ),
                itemBuilder: (_, index) => _OrderTableCard(
                  table: tables[index],
                  order: _tableOrder(tables[index]),
                  canManageQr: context.read<AuthProvider>().currentUser?.canManageTables ?? false,
                  onOpen: () => _openOrderTable(tables[index]),
                  onQr: () => _openTableQr(tables[index]),
                ),
              );
            },
          ),
      ],
    );
  }

  Order? _tableOrder(CafeTable table) {
    final orders = _orders ?? const <Order>[];
    for (final order in orders) {
      if (order.tableId == table.id && order.status != 'completed' && order.status != 'voided') {
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
      MaterialPageRoute(builder: (_) => QrManagementScreen(focusTableId: table.id)),
    );
    if (mounted) _load();
  }

  /*
   * One clean "Filters" control instead of three separate chip rows.
   * Tapping it opens a bottom sheet with Date/Period, Payment Type and
   * Order Type selectors plus Apply/Clear actions. A compact summary is
   * shown next to the button so the active filters stay visible without
   * cluttering the screen.
   */
  Widget _buildFilters() {
    final hasActiveFilters = _activeFilterCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _openFilterSheet,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasActiveFilters
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 20,
                      color: hasActiveFilters
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasActiveFilters
                            ? '$_dateRangeSummary'
                                '${_filterPayment != null ? ' · $_filterPayment' : ''}'
                                '${_filterOrderType != null ? ' · ${_orderTypeLabel(_filterOrderType!)}' : ''}'
                            : 'Filters',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: hasActiveFilters
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (hasActiveFilters)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasActiveFilters) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear Filters',
              onPressed: () {
                setState(() {
                  _filterRange = 'Today';
                  _filterPayment = null;
                  _filterOrderType = null;
                  _customFrom = null;
                  _customTo = null;
                });
                _load();
              },
              icon: Icon(
                Icons.close,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    // Local, uncommitted copies so changes only take effect on "Apply".
    var pendingRange = _filterRange;
    var pendingPayment = _filterPayment;
    var pendingOrderType = _filterOrderType;
    var pendingFrom = _customFrom;
    var pendingTo = _customTo;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> pickCustomRange() async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: sheetContext,
                firstDate: DateTime(now.year - 2),
                lastDate: now,
                initialDateRange: (pendingFrom != null && pendingTo != null)
                    ? DateTimeRange(start: pendingFrom!, end: pendingTo!)
                    : DateTimeRange(start: now, end: now),
              );

              if (picked != null) {
                setSheetState(() {
                  pendingRange = 'Custom';
                  pendingFrom = picked.start;
                  pendingTo = picked.end;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            pendingRange = 'Today';
                            pendingPayment = null;
                            pendingOrderType = null;
                            pendingFrom = null;
                            pendingTo = null;
                          });
                        },
                        child: const Text('Clear Filters'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Date / Period',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: pendingRange,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                    items: _dateRangeOptions.map((label) {
                      return DropdownMenuItem(
                        value: label,
                        child: Text(
                          label == 'Custom' &&
                                  pendingFrom != null &&
                                  pendingTo != null
                              ? 'Custom: ${Formatters.shortDate(pendingFrom!)} – '
                                  '${Formatters.shortDate(pendingTo!)}'
                              : label,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      if (value == null) return;

                      if (value == 'Custom') {
                        await pickCustomRange();
                        return;
                      }

                      setSheetState(() {
                        pendingRange = value;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Payment Type',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: pendingPayment,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Payment Types'),
                      ),
                      ..._paymentMethodOptions.map(
                        (method) => DropdownMenuItem<String?>(
                          value: method,
                          child: Text(method),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setSheetState(() {
                        pendingPayment = value;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Order Type',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: pendingOrderType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Types'),
                      ),
                      ..._orderTypeOptions.map(
                        (type) => DropdownMenuItem<String?>(
                          value: type,
                          child: Text(_orderTypeLabel(type)),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setSheetState(() {
                        pendingOrderType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();

                        setState(() {
                          _filterRange = pendingRange;
                          _filterPayment = pendingPayment;
                          _filterOrderType = pendingOrderType;
                          _customFrom = pendingFrom;
                          _customTo = pendingTo;
                        });

                        _load();
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

  bool get _isBilling => order != null &&
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
        return AppColors.danger;
      case 'Billing':
        return AppColors.warning;
      case 'Reserved':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _ageText() {
    final at = table.latestOpenOrderAt;
    if (at == null) return '';
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'}';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    final itemPreview = order?.items.take(2).toList() ?? const <OrderItem>[];

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: table.isOccupied
                ? statusColor.withValues(alpha: .28)
                : AppColors.border,
            width: table.isOccupied ? 1.3 : 1,
          ),
          boxShadow: const [
            BoxShadow(blurRadius: 9, offset: Offset(0, 3), color: Color(0x08000000)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    table.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: IconButton(
                    tooltip: table.hasQrNumber ? 'View QR' : 'Set up QR',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.qr_code_2_outlined, color: AppColors.primary, size: 21),
                    onPressed: canManageQr || table.hasQrNumber ? onQr : onOpen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                Icon(Icons.people_outline, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text('${order != null ? order!.items.fold<int>(0, (sum, item) => sum + item.quantity) : table.capacity} ${order != null ? 'Items' : 'Seats'}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: order == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_restaurant_outlined, size: 36, color: AppColors.primary.withValues(alpha: .75)),
                          const SizedBox(height: 5),
                          Text('${table.capacity} Seats', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...itemPreview.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                children: [
                                  Icon(Icons.restaurant_outlined, size: 16, color: AppColors.textMuted),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                                  Text('×${item.quantity}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            )),
                        if (order!.items.length > 2)
                          Text('+${order!.items.length - 2} more items', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        if (_ageText().isNotEmpty) ...[
                          const Spacer(),
                          Row(
                            children: [
                              Icon(Icons.schedule_outlined, size: 15, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(_ageText(), style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(
                  order != null
                      ? Icons.receipt_long_outlined
                      : table.isOccupied
                          ? Icons.table_restaurant_outlined
                          : Icons.qr_code_2,
                  size: 18,
                ),
                label: Text(
                  order != null
                      ? 'View Order'
                      : table.isOccupied
                          ? 'Open Table'
                          : 'Scan QR / Open Table',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;
  final VoidCallback onChanged;

  const _OrderTile({
    required this.order,
    required this.onChanged,
  });

  /*
   * Only today's unattended QR open order gets NEW QR label.
   */
  bool _isNewQrOrder() {
    if (!order.isQrOrder ||
        order.status != 'open' ||
        order.staffName != null) {
      return false;
    }

    final now = DateTime.now();
    final created = order.createdAt.toLocal();

    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    // 'payment_initiated' means a customer tapped "Pay with UPI" on the QR
    // menu and was handed off to a UPI app — NOT proof of payment. Staff
    // still see this as an ordinary pending/unpaid order until they verify
    // and check it out.
    final paymentPending =
        order.paymentStatus == 'pending' ||
        order.paymentStatus == 'payment_initiated';

    final paymentColor =
        order.paymentStatus == 'paid'
            ? AppColors.success
            : ((order.paymentStatus == 'failed' ||
                    order.paymentStatus ==
                        'cancelled')
                ? AppColors.danger
                : AppColors.warning);

    final isNewQrOrder =
        _isNewQrOrder();

    /*
     * An ordinary old/open POS order should NOT look like
     * a NEW QR order.
     */
    final isOpenOrder =
        order.status == 'open';

    final statusColor = isNewQrOrder
        ? AppColors.warning
        : order.status == 'preparing'
            ? AppColors.info
            : order.status == 'ready'
                ? AppColors.success
                : AppColors.textMuted;

    final statusLabel = isNewQrOrder
        ? 'NEW'
        : order.status.toUpperCase();

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
            ),
          ),
        );

        onChanged();
      },
      borderRadius:
          BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(14),

          /*
           * Amber border ONLY for today's NEW QR orders.
           */
          border: Border.all(
            color: isNewQrOrder
                ? AppColors.warning
                : AppColors.border,
            width:
                isNewQrOrder ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${order.orderNumber}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),

                      /*
                       * QR badge remains visible for all QR orders.
                       * This does NOT mean NEW.
                       */
                      if (order.isQrOrder) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration:
                              BoxDecoration(
                            color: AppColors
                                .accent
                                .withValues(
                              alpha: 0.15,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(4),
                          ),
                          child: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2,
                                size: 10,
                                color: AppColors
                                    .primaryDark,
                              ),
                              const SizedBox(
                                width: 2,
                              ),
                              Text(
                                'QR ORDER',
                                style:
                                    TextStyle(
                                  color: AppColors
                                      .primaryDark,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (order.status ==
                          'voided') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration:
                              BoxDecoration(
                            color: AppColors
                                .danger
                                .withValues(
                              alpha: 0.1,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(4),
                          ),
                          child: Text(
                            'VOIDED',
                            style: TextStyle(
                              color:
                                  AppColors.danger,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    Formatters.dateTime(
                      order.createdAt,
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),

                  Text(
                    order.orderType ==
                            'dine_in'
                        ? 'Dine-In'
                            '${order.tableName != null ? ' · ${order.tableName}' : ''}'
                            '${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                        : order.orderType ==
                                'delivery'
                            ? 'Delivery'
                            : 'Takeaway',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),

                  if (order.staffName != null)
                    Text(
                      'Attended by: ${order.staffName}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    )
                  else if (isNewQrOrder)
                    Text(
                      'Awaiting staff',
                      style: TextStyle(
                        color:
                            AppColors.textMuted,
                      ),
                    )
                  else if (order.isQrOrder &&
                      isOpenOrder)
                    Text(
                      'Unattended',
                      style: TextStyle(
                        color:
                            AppColors.textMuted,
                      ),
                    ),

                  if (order.qrCustomerContact
                              ?.name !=
                          null ||
                      order.qrCustomerContact
                              ?.phone !=
                          null)
                    Text(
                      [
                        order.qrCustomerContact
                            ?.name,
                        order.qrCustomerContact
                            ?.phone,
                      ]
                          .where(
                            (value) =>
                                value != null &&
                                value.isNotEmpty,
                          )
                          .join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(
                    order.grandTotal,
                  ),
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 4),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      /*
                       * STATUS
                       */
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration:
                            BoxDecoration(
                          color: statusColor
                              .withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style:
                              TextStyle(
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w800,
                            color:
                                statusColor,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      /*
                       * PAYMENT STATUS
                       */
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration:
                            BoxDecoration(
                          color: paymentColor
                              .withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(6),
                        ),
                        child: Text(
                          order.paymentStatus ==
                                  'paid'
                              ? '${order.paymentMethod} · PAID'
                              : paymentPending
                                  ? '${order.paymentMethod} · PENDING'
                                  : '${order.paymentMethod} · ${order.paymentStatus.toUpperCase()}',
                          style:
                              TextStyle(
                            color:
                                paymentColor,
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}