import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../models/order.dart';
import '../../services/counter_service.dart';
import '../../services/order_service.dart';
import 'direct_order_screen.dart';
import 'running_orders_bar.dart';

/// Takeaway or Delivery counters on a page of their own (from New Sale).
class CounterSlotsScreen extends StatefulWidget {
  /// 'takeaway' or 'delivery'.
  final String orderType;

  const CounterSlotsScreen({super.key, required this.orderType})
      : assert(orderType == 'takeaway' || orderType == 'delivery');

  @override
  State<CounterSlotsScreen> createState() => _CounterSlotsScreenState();
}

class _CounterSlotsScreenState extends State<CounterSlotsScreen> {
  final GlobalKey<CountersPanelState> _panelKey = GlobalKey<CountersPanelState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orderType == 'delivery' ? 'Delivery' : 'Takeaway'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _panelKey.currentState?.refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _panelKey.currentState?.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [CountersPanel(key: _panelKey, orderType: widget.orderType)],
        ),
      ),
    );
  }
}

/// Takeaway (T1, T2...) or Delivery (D1, D2...) counters, shown like the
/// dine-in tables: Occupied / Billing / Available. Each counter holds one
/// running (unbilled) order; tapping it opens the menu for that counter.
/// Counters are kept on the server, so one added on any device shows on
/// every device. Used on its own page and inside the Tables and Orders
/// pages.
class CountersPanel extends StatefulWidget {
  /// 'takeaway' or 'delivery'.
  final String orderType;

  const CountersPanel({super.key, required this.orderType})
      : assert(orderType == 'takeaway' || orderType == 'delivery');

  @override
  State<CountersPanel> createState() => CountersPanelState();
}

class CountersPanelState extends State<CountersPanel> {
  static const List<int> _defaultCounters = [1, 2, 3, 4];

  final CounterService _counterService = CounterService();
  List<int> _counters = _defaultCounters;
  List<Order> _orders = const [];
  bool _loading = true;
  bool _busyAction = false;
  String? _error;

  bool get _isDelivery => widget.orderType == 'delivery';
  String get _prefix => SlotLabel.prefixFor(widget.orderType);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Reloads counters and running orders from the server. [silent] skips
  /// the progress bar, for background polling.
  Future<void> refresh({bool silent = false}) async {
    if (mounted && !silent) setState(() => _loading = true);
    String? error;
    await Future.wait([
      _counterService.list(widget.orderType).then((counters) {
        if (mounted && counters.isNotEmpty) setState(() => _counters = counters);
      }).catchError((Object e) {
        // An older server without counters still shows the default T1-T4.
        error ??= e is ApiException ? e.message : 'Could not load counters.';
      }),
      OrderService()
          .list(orderType: widget.orderType, status: 'active', limit: 100)
          .then((orders) {
        if (!mounted) return;
        setState(() {
          _orders = orders.where((o) => o.paymentStatus != 'paid').toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
      }).catchError((Object e) {
        error = e is ApiException ? e.message : 'Could not load running orders.';
      }),
    ]);
    if (mounted) setState(() { _loading = false; _error = error; });
  }

  /// Busy counter number -> its order. A second order on the same counter
  /// (e.g. from another device) is listed separately so it is never hidden.
  Map<int, Order> get _busy {
    final result = <int, Order>{};
    for (final order in _orders) {
      final slot = SlotLabel.parse(order.tableCustomerLabel, widget.orderType);
      if (slot != null) result.putIfAbsent(slot.number, () => order);
    }
    return result;
  }

  /// Saved counters plus any busy counter that is no longer saved.
  List<int> get _visibleCounters => ({..._counters, ..._busy.keys}.toList()..sort());

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open({String? slot, Order? order}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DirectOrderScreen(
          orderType: widget.orderType,
          slot: slot,
          resumeOrderId: order?.id,
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _addCounter() => _runAction(() async {
        final before = _counters.toSet();
        final counters = await _counterService.add(widget.orderType);
        if (!mounted) return;
        setState(() => _counters = counters);
        final added = counters.where((n) => !before.contains(n));
        _snack(added.isEmpty ? 'Counter added' : '$_prefix${added.first} added');
      });

  Future<void> _removeCounter(int number) async {
    if (_busy.containsKey(number)) {
      _snack('$_prefix$number has a running order. Bill or cancel it first.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $_prefix$number'),
        content: Text('Remove counter $_prefix$number? You can add it again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(() async {
      final counters = await _counterService.remove(widget.orderType, number);
      if (!mounted) return;
      setState(() => _counters = counters);
      _snack('$_prefix$number removed');
    });
  }

  Future<void> _cancelOrder(Order order, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text('Cancel the running order on $title (${Formatters.currency(order.grandTotal)})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Order')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(() async {
      await OrderService().cancelOpenOrder(order.id);
      await refresh();
      if (mounted) _snack('Order on $title cancelled.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;
    final unslotted = _orders.where((o) => !busy.values.contains(o)).toList();
    final counters = _visibleCounters;
    final occupied = busy.length + unslotted.length;
    final available = counters.where((n) => !busy.containsKey(n)).length;

    final cards = <Widget>[
      for (final number in counters)
        _CounterCard(
          title: '$_prefix$number',
          order: busy[number],
          isDelivery: _isDelivery,
          onOpen: () => _open(slot: '$_prefix$number', order: busy[number]),
          onRemove: busy[number] == null ? () => _removeCounter(number) : null,
          onCancelOrder: busy[number] == null
              ? null
              : () => _cancelOrder(busy[number]!, '$_prefix$number'),
        ),
      for (final order in unslotted)
        _CounterCard(
          title: '#${order.orderNumber}',
          order: order,
          isDelivery: _isDelivery,
          onOpen: () => _open(order: order),
          onCancelOrder: () => _cancelOrder(order, '#${order.orderNumber}'),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(0, 3), color: Color(0x0A000000))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Icon(
                  _isDelivery ? Icons.delivery_dining_outlined : Icons.shopping_bag_outlined,
                  color: AppColors.primary,
                  size: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isDelivery ? 'Delivery Counters' : 'Takeaway Counters',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: '$occupied',
                            style: const TextStyle(color: FreshUi.amber, fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: ' occupied  •  '),
                          TextSpan(
                            text: '$available',
                            style: const TextStyle(color: FreshUi.green, fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: ' available'),
                        ]),
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busyAction ? null : _addCounter,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else Divider(height: 2, color: AppColors.border),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('$_error Pull down to retry.', style: TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth >= 760 ? 3 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 206,
                ),
                itemBuilder: (_, index) => cards[index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A counter card in the same style as a dine-in table card on the Orders
/// page: status pill, name, items/age, item preview and an action button.
class _CounterCard extends StatelessWidget {
  final String title;
  final Order? order;
  final bool isDelivery;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;
  final VoidCallback? onCancelOrder;

  const _CounterCard({
    required this.title,
    required this.order,
    required this.isDelivery,
    required this.onOpen,
    this.onRemove,
    this.onCancelOrder,
  });

  bool get _isBilling =>
      order != null &&
      order!.paymentStatus == 'pending' &&
      (order!.status == 'ready' || order!.status == 'preparing');

  String get _status {
    if (_isBilling) return 'Billing';
    if (order != null) return 'Occupied';
    return 'Available';
  }

  Color get _statusColor {
    if (_isBilling) return FreshUi.amber;
    if (order != null) return FreshUi.red;
    return FreshUi.green;
  }

  String _ageText(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '$minutes mins';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'}';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text(order == null ? 'Start Order' : 'View Order'),
              onTap: () {
                Navigator.pop(sheetContext);
                onOpen();
              },
            ),
            if (onCancelOrder != null)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Cancel Order'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onCancelOrder!();
                },
              ),
            if (onRemove != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('Remove $title'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRemove!();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = this.order;
    final color = _statusColor;
    final items = order?.items ?? const <OrderItem>[];
    final itemCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final name = SlotLabel.parse(order?.tableCustomerLabel, order?.orderType ?? '')?.name ?? '';
    final customer = name.isNotEmpty ? name : (order?.customerName ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: FreshUi.card(tint: color, tintStrength: .05),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _status,
                            style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          customer.isEmpty ? title : '$title · $customer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showMenu(context),
                      borderRadius: BorderRadius.circular(9),
                      child: Ink(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(Icons.more_horiz, color: AppColors.textSecondary, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: _meta(
                      order != null ? Icons.receipt_long_outlined : Icons.check_circle_outline,
                      order != null ? '$itemCount Items' : 'No orders',
                    ),
                  ),
                  if (order != null) ...[
                    Container(
                      width: 1,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: AppColors.border,
                    ),
                    Expanded(child: _meta(Icons.schedule_rounded, _ageText(order.createdAt))),
                  ],
                ],
              ),
              Expanded(
                child: order == null
                    ? Center(
                        child: Icon(
                          isDelivery ? Icons.delivery_dining_outlined : Icons.shopping_bag_outlined,
                          size: 32,
                          color: color.withValues(alpha: .7),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(height: 12, color: AppColors.border.withValues(alpha: .8)),
                          ...items.take(2).map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.restaurant_rounded, size: 13, color: AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                                      ),
                                    ),
                                    Text('×${item.quantity}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                  ],
                                ),
                              )),
                          const Spacer(),
                          Text(
                            Formatters.currency(order.grandTotal),
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              FreshGradientButton(
                onPressed: onOpen,
                height: 34,
                gradient: order != null
                    ? (_isBilling ? FreshUi.amberGradient : FreshUi.redGradient)
                    : FreshUi.greenGradient,
                icon: order != null ? Icons.visibility_outlined : Icons.add_circle_outline_rounded,
                label: order != null ? 'View Order' : 'Start Order',
              ),
            ],
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
