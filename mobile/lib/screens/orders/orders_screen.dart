import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';

import 'order_detail_screen.dart';
import 'kitchen_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with WidgetsBindingObserver {
  final _service = OrderService();

  List<Order>? _orders;

  bool _isRefreshing = true;
  String? _error;

  Timer? _qrPollTimer;

  /*
   * Only today's NEW QR orders are tracked here.
   */
  final Set<String> _knownQrOrderIds = {};

  bool _hasSeededQrOrders = false;

  /*
   * Kitchen badge only counts today's unattended/open QR orders.
   */
  int _pendingKitchenCount = 0;

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
    _refreshKitchenBadge();

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
                } else {
                  navState?.push(
                    MaterialPageRoute(
                      builder: (_) => const KitchenScreen(),
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

  /*
   * Kitchen badge.
   *
   * IMPORTANT:
   * Only today's NEW/unattended QR orders are counted.
   */
  Future<void> _refreshKitchenBadge() async {
    try {
      final kitchenOrders = await _service.kitchenOrders();

      if (!mounted) return;

      final pendingToday = kitchenOrders.where((order) {
        return _isNewQrOrder(order);
      }).length;

      setState(() {
        _pendingKitchenCount = pendingToday;
      });
    } catch (_) {
      /*
       * Badge is only a convenience indicator.
       * Keep last known value on failure.
       */
    }
  }

  DateTime? get _fromDate {
    final now = DateTime.now();

    switch (_filterRange) {
      case 'Today':
        return DateTime(
          now.year,
          now.month,
          now.day,
        );

      case 'Yesterday':
        return DateTime(
          now.year,
          now.month,
          now.day - 1,
        );

      case 'This Week':
        return now.subtract(
          Duration(days: now.weekday % 7),
        );

      case 'This Month':
        return DateTime(
          now.year,
          now.month,
          1,
        );

      case 'Custom':
        if (_customFrom == null) return null;
        return DateTime(
          _customFrom!.year,
          _customFrom!.month,
          _customFrom!.day,
        );

      default:
        return null;
    }
  }

  DateTime? get _toDate {
    if (_filterRange == 'Yesterday') {
      final now = DateTime.now();

      return DateTime(
        now.year,
        now.month,
        now.day - 1,
        23,
        59,
        59,
      );
    }

    if (_filterRange == 'Custom' && _customTo != null) {
      return DateTime(
        _customTo!.year,
        _customTo!.month,
        _customTo!.day,
        23,
        59,
        59,
      );
    }

    return null;
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
    _refreshKitchenBadge();

    try {
      final orders = await _service.list(
        from: _fromDate,
        to: _toDate,
        paymentMethod: _filterPayment,
        orderType: _filterOrderType,
      );

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
        title: const Text('Orders'),
        actions: [
          IconButton(
            tooltip: _pendingKitchenCount > 0
                ? '$_pendingKitchenCount order'
                    '${_pendingKitchenCount == 1 ? '' : 's'} '
                    'awaiting confirmation'
                : 'Kitchen Display',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const KitchenScreen(),
                ),
              );

              _refreshKitchenBadge();
            },
            icon: Badge(
              isLabelVisible: _pendingKitchenCount > 0,
              label: Text(
                '$_pendingKitchenCount',
              ),
              backgroundColor: AppColors.warning,
              child: Icon(
                Icons.restaurant_menu_outlined,
                color: _pendingKitchenCount > 0
                    ? AppColors.warning
                    : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final orders = _orders;

    /*
     * Nothing loaded yet.
     */
    if (orders == null && _isRefreshing) {
      return LoadingState();
    }

    /*
     * First load failed.
     */
    if (orders == null && _error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _load,
      );
    }

    if (orders == null) {
      return LoadingState();
    }

    /*
     * No orders.
     */
    if (orders.isEmpty) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                0,
              ),
              child: InlineRetryBanner(
                message: 'Could not refresh. $_error',
                onRetry: _load,
              ),
            ),
          Expanded(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders found',
              subtitle:
                  'Try a different filter or date range.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length +
            (_error != null ? 1 : 0),
        separatorBuilder: (_, __) =>
            const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_error != null && index == 0) {
            return InlineRetryBanner(
              message:
                  'Could not refresh. Showing the last loaded orders.',
              onRetry: _load,
            );
          }

          final orderIndex =
              _error != null ? index - 1 : index;

          return _OrderTile(
            order: orders[orderIndex],
            onChanged: _load,
          );
        },
      ),
    );
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
        padding: const EdgeInsets.all(14),
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