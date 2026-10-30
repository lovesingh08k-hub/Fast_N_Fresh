import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pos_debug_log.dart';
import '../../models/cart_item.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import '../../services/order_service.dart';

/// Saves the cart as an open (unbilled) order on the server, or updates the
/// open order it already belongs to. On a first save the cart is linked to
/// the new order (cart.openOrderId).
Future<Order> saveCartAsOpenOrder(CartProvider cart) async {
  final service = OrderService();

  if (cart.openOrderId != null) {
    await service.updateOpenOrderItems(
      cart.openOrderId!,
      items: cart.items,
      discount: cart.discount,
      notes: cart.notes,
      customerId: cart.selectedCustomer?.id,
      tableCustomerLabel: cart.openOrderLabelUpdate,
      extra: cart.billAdjustments,
    );
    return service.getById(cart.openOrderId!);
  }

  final order = await service.startOpenOrder(
    orderType: cart.orderType,
    tableId: cart.tableId,
    tableCustomerLabel: cart.effectiveCustomerLabel,
    customerId: cart.selectedCustomer?.id,
    notes: cart.notes,
    deliveryInfo: cart.orderType == 'delivery'
        ? {
            'address': cart.deliveryAddress.trim(),
            'phone': cart.deliveryPhone.trim(),
          }
        : null,
  );
  await service.updateOpenOrderItems(
    order.id,
    items: cart.items,
    discount: cart.discount,
    notes: cart.notes,
    customerId: cart.selectedCustomer?.id,
    extra: cart.billAdjustments,
  );
  cart.configureContext(
    orderType: cart.orderType,
    tableId: cart.tableId,
    tableName: cart.tableName,
    tableCustomerLabel: cart.effectiveCustomerLabel,
    openOrderId: order.id,
  );
  return order;
}

/// [saveCartAsOpenOrder] with a snackbar for the result. Returns true on
/// success, so callers never throw away a cart that failed to save.
Future<bool> saveCartWithFeedback(BuildContext context) async {
  final cart = context.read<CartProvider>();
  if (cart.isEmpty) return false;

  final messenger = ScaffoldMessenger.of(context);
  final refreshBus = context.read<TabRefreshBus>();
  try {
    final order = await saveCartAsOpenOrder(cart);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Order #${order.orderNumber} saved')));
    refreshBus.bumpDashboard();
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save the order. Please try again.')),
    );
  }
  return false;
}

/// A counter slot tag read from an order label: "T1" or "T1 · Rahul".
class SlotLabel {
  static final RegExp _pattern = RegExp(r'^([TD])(\d+)(?: · (.*))?$');

  /// "T" for takeaway, "D" for delivery.
  final String prefix;
  final int number;

  /// Name typed after the tag, or empty.
  final String name;

  const SlotLabel(this.prefix, this.number, this.name);

  String get tag => '$prefix$number';

  static String prefixFor(String orderType) => orderType == 'delivery' ? 'D' : 'T';

  /// The slot in [label], or null when it is not a slot of [orderType].
  static SlotLabel? parse(String? label, String orderType) {
    final match = _pattern.firstMatch(label?.trim() ?? '');
    if (match == null || match.group(1) != prefixFor(orderType)) return null;
    return SlotLabel(match.group(1)!, int.parse(match.group(2)!), match.group(3)?.trim() ?? '');
  }
}

/// Re-reads open order [orderId] from the server (latest items from any
/// device) and loads it into [cart] so it can be edited or billed.
Future<Order> loadOpenOrderIntoCart(CartProvider cart, String orderId) async {
  final latest = await OrderService().getById(orderId);
  final slot = SlotLabel.parse(latest.tableCustomerLabel, latest.orderType);

  cart.configureContext(
    orderType: latest.orderType,
    tableCustomerLabel: slot?.tag ?? latest.tableCustomerLabel,
    openOrderId: latest.id,
  );
  if (slot != null) cart.setCustomerNameInput(slot.name);
  cart.hydrateFromOpenOrder(
    items: latest.items
        .map(
          (oi) => CartItem(
            product: Product(
              id: oi.productId,
              name: oi.name,
              categoryId: '',
              sellingPrice: oi.price,
              imageUrl: oi.imageUrl,
              taxRate: oi.taxRate,
            ),
            quantity: oi.quantity,
            note: oi.note ?? '',
          ),
        )
        .toList(),
    discount: latest.discount,
    customer: latest.customerId == null
        ? null
        : Customer(
            id: latest.customerId!,
            name: latest.customerName ?? '',
            phone: latest.customerPhone ?? '',
          ),
  );
  if (latest.orderType == 'delivery') {
    cart.deliveryAddress = latest.deliveryInfo?.address ?? '';
    cart.deliveryPhone = latest.deliveryInfo?.phone ?? '';
  }
  cart.notes = latest.notes ?? '';
  cart.restoreAdjustments(latest.bill, serviceCharge: latest.serviceChargeEnabled, deliveryCharge: latest.deliveryChargeOverride);
  return latest;
}

/// Counter slots for Takeaway (T1, T2...) and Delivery (D1, D2...), like
/// tables for dine-in. Each slot holds one running (unbilled) order, so
/// several customers can be served before any of them is billed. Tapping a
/// free slot saves the current cart and starts a new order there; tapping a
/// busy slot saves the current cart and loads that order back. "Add more"
/// opens another slot. Open orders live on the server, so they survive app
/// restarts and show on every device.
class RunningOrdersBar extends StatefulWidget {
  /// 'takeaway' or 'delivery'.
  final String orderType;

  const RunningOrdersBar({super.key, required this.orderType});

  @override
  State<RunningOrdersBar> createState() => RunningOrdersBarState();
}

class RunningOrdersBarState extends State<RunningOrdersBar> {
  static const int _defaultSlots = 4;


  List<Order> _orders = const [];
  int _slotCount = _defaultSlots;
  bool _switching = false;

  String get _prefix => SlotLabel.prefixFor(widget.orderType);
  String get _prefsKey => 'counter_slots_${widget.orderType}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSlotCount());
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(RunningOrdersBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderType != widget.orderType) {
      setState(() {
        _orders = const [];
        _slotCount = _defaultSlots;
      });
      unawaited(_loadSlotCount());
      unawaited(refresh());
    }
  }

  Future<void> _loadSlotCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsKey);
      if (saved != null && mounted) {
        setState(() => _slotCount = max(saved, _defaultSlots));
      }
    } catch (e) {
      posLog('Could not read counter slot count: $e');
    }
  }

  Future<void> _saveSlotCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, _slotCount);
    } catch (e) {
      posLog('Could not save counter slot count: $e');
    }
  }

  /// Slot number of [order], or null for an order saved without a slot.
  int? _slotOf(Order order) =>
      SlotLabel.parse(order.tableCustomerLabel, widget.orderType)?.number;

  /// Busy slots -> their order. A second order in the same slot (e.g. from
  /// another device) is shown separately so it is never hidden.
  Map<int, Order> get _slotOrders {
    final result = <int, Order>{};
    for (final order in _orders) {
      final slot = _slotOf(order);
      if (slot != null) result.putIfAbsent(slot, () => order);
    }
    return result;
  }

  int get _visibleSlots =>
      _slotOrders.keys.fold(_slotCount, (count, slot) => max(count, slot));

  int? _currentSlot(CartProvider cart) {
    if (!cart.hasSlot || !cart.tableCustomerLabel!.startsWith(_prefix)) return null;
    return int.tryParse(cart.tableCustomerLabel!.substring(1));
  }

  /// Reloads the list from the server (e.g. after saving or billing).
  Future<void> refresh() async {
    final type = widget.orderType;
    try {
      final orders = await OrderService().list(
        orderType: type,
        status: 'active',
        limit: 50,
      );
      if (!mounted || type != widget.orderType) return;
      setState(() {
        _orders = orders.where((o) => o.paymentStatus != 'paid').toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });
      _ensureSlotSelected();
    } catch (e) {
      posLog('Could not load running $type orders: $e');
    }
  }

  /// An empty new cart always sits in a free slot, so the order saved from
  /// it gets a T/D number.
  void _ensureSlotSelected() {
    final cart = context.read<CartProvider>();
    if (_switching || cart.openOrderId != null || !cart.isEmpty) return;
    final busy = _slotOrders;
    final current = _currentSlot(cart);
    if (current != null && !busy.containsKey(current)) return;

    var slot = 1;
    while (busy.containsKey(slot)) {
      slot++;
    }
    if (slot > _visibleSlots) {
      setState(() => _slotCount = slot);
      unawaited(_saveSlotCount());
    }
    cart.configureContext(
      orderType: widget.orderType,
      tableCustomerLabel: '$_prefix$slot',
    );
  }

  Future<bool> _parkCurrentCart() async {
    if (context.read<CartProvider>().isEmpty) return true;
    return saveCartWithFeedback(context);
  }

  Future<void> _openFreeSlot(int slot) async {
    final cart = context.read<CartProvider>();
    if (_switching) return;
    if (cart.openOrderId == null && _currentSlot(cart) == slot) return;
    setState(() => _switching = true);
    try {
      if (!await _parkCurrentCart() || !mounted) return;
      cart.clearItems();
      cart.configureContext(
        orderType: widget.orderType,
        tableCustomerLabel: '$_prefix$slot',
      );
    } finally {
      if (mounted) setState(() => _switching = false);
      unawaited(refresh());
    }
  }

  Future<void> _addSlot() async {
    final slot = _visibleSlots + 1;
    setState(() => _slotCount = slot);
    unawaited(_saveSlotCount());
    await _openFreeSlot(slot);
  }

  /// Long-press on the last extra slot removes it again, when it is free.
  void _removeSlot(int slot) {
    final cart = context.read<CartProvider>();
    final holdsItems = _currentSlot(cart) == slot && !cart.isEmpty;
    if (slot != _visibleSlots || slot <= _defaultSlots || holdsItems) return;
    setState(() => _slotCount = slot - 1);
    unawaited(_saveSlotCount());
    if (_currentSlot(cart) == slot) {
      cart.configureContext(orderType: widget.orderType);
      _ensureSlotSelected();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_prefix$slot removed')),
    );
  }

  /// Loads an open order into the cart, e.g. when a pending bill is opened
  /// from Bill History. Returns false if it could not be loaded.
  Future<bool> resumeById(String orderId) => _resume(orderId);

  Future<bool> _resume(String orderId) async {
    final cart = context.read<CartProvider>();
    if (cart.openOrderId == orderId) return true;
    if (_switching) return false;
    setState(() => _switching = true);
    try {
      if (!await _parkCurrentCart() || !mounted) return false;

      await loadOpenOrderIntoCart(cart, orderId);
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that order. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _switching = false);
      unawaited(refresh());
    }
    return false;
  }

  String _label(Order order, {String? slot}) {
    final label = order.tableCustomerLabel?.trim() ?? '';
    final customer = order.customerName?.trim() ?? '';
    String? name;
    if (slot != null) {
      final typed = SlotLabel.parse(label, widget.orderType)?.name ?? '';
      name = typed.isNotEmpty ? typed : (customer.isNotEmpty ? customer : null);
    } else {
      name = label.isNotEmpty ? label : (customer.isNotEmpty ? customer : null);
    }
    return [
      slot ?? '#${order.orderNumber}',
      if (name != null) name,
      Formatters.currency(order.grandTotal),
    ].join(' · ');
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool busy = false,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        avatar: busy
            ? Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.warning)
            : null,
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        side: busy && !selected
            ? BorderSide(color: AppColors.warning.withValues(alpha: .6))
            : null,
        onSelected: onTap == null ? null : (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final busy = _slotOrders;
    final unslotted = _orders.where((o) => !busy.values.contains(o)).toList();
    final currentSlot = cart.openOrderId == null ? _currentSlot(cart) : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _orders.isEmpty ? 'Running orders' : 'Running orders (${_orders.length})',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var slot = 1; slot <= _visibleSlots; slot++)
                if (busy[slot] case final order?)
                  _chip(
                    label: _label(order, slot: '$_prefix$slot'),
                    busy: true,
                    selected: cart.openOrderId == order.id,
                    onTap: _switching ? null : () => _resume(order.id),
                  )
                else
                  _chip(
                    label: '$_prefix$slot',
                    selected: currentSlot == slot,
                    onTap: _switching ? null : () => _openFreeSlot(slot),
                    onLongPress: () => _removeSlot(slot),
                  ),
              for (final order in unslotted)
                _chip(
                  label: _label(order),
                  busy: true,
                  selected: cart.openOrderId == order.id,
                  onTap: _switching ? null : () => _resume(order.id),
                ),
              ActionChip(
                avatar: Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                label: const Text('Add more'),
                onPressed: _switching ? null : _addSlot,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
