import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../core/widgets/order_flow_stepper.dart';
import '../../core/widgets/product_image.dart';
import '../../models/table.dart';
import '../../models/order.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';
import '../../services/table_service.dart';
import '../../services/order_service.dart';
import '../../services/kot_service.dart';
import '../../services/misc_services.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../pos/pos_screen.dart';
import '../pos/customer_picker_sheet.dart';
import '../pos/add_items_sheet.dart';
import 'table_form_screen.dart';
import 'qr_management_screen.dart';
import '../settings/printer_choice_sheet.dart';
import '../../services/bluetooth_printer_service.dart';

class TableDetailScreen extends StatefulWidget {
  final String tableId;
  const TableDetailScreen({super.key, required this.tableId});

  @override
  State<TableDetailScreen> createState() => _TableDetailScreenState();
}

class _TableDetailScreenState extends State<TableDetailScreen> with WidgetsBindingObserver {
  final TableService _service = TableService();
  final OrderService _orderService = OrderService();
  CafeTable? _table;
  List<Order> _openOrders = [];
  bool _loading = true;
  bool _starting = false;
  String? _error;
  final Set<String> _busyOrders = {};
  final Set<String> _servedOrderIds = {};

  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;
  Timer? _refreshTimer;

  int get _totalItems => _openOrders.fold(0, (sum, order) => sum + order.items.fold(0, (s, i) => s + i.quantity));
  int get _servedItems => _openOrders.where((o) => _servedOrderIds.contains(o.id)).fold(0, (sum, order) => sum + order.items.fold(0, (s, i) => s + i.quantity));
  int get _servedPercent => _totalItems == 0 ? 0 : ((_servedItems / _totalItems) * 100).round();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Keep the table screen live so order updates appear here without
    // forcing the staff to leave the table and open another page.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_loading && _busyOrders.isEmpty) _refreshSilently();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<ConnectivityProvider>();
    if (!identical(c, _connectivity)) {
      _connectivity?.removeListener(_onConnectivity);
      _connectivity = c;
      _wasOnline = c.isOnline;
      _connectivity!.addListener(_onConnectivity);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _connectivity?.removeListener(_onConnectivity);
    super.dispose();
  }

  void _onConnectivity() {
    final online = _connectivity?.isOnline ?? true;
    if (online && !_wasOnline && _error != null) _load();
    _wasOnline = online;
  }

  String get _servedKey => 'served_orders_${widget.tableId}';

  Future<void> _persistServedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_servedKey, jsonEncode(_servedOrderIds.toList()));
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await _service.getDetail(widget.tableId);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_servedKey);
      final served = <String>{};
      if (raw != null) {
        try {
          served.addAll((jsonDecode(raw) as List<dynamic>).whereType<String>());
        } catch (_) {}
      }
      final activeIds = result.$2.map((o) => o.id).toSet();
      served.removeWhere((id) => !activeIds.contains(id));
      await prefs.setString(_servedKey, jsonEncode(served.toList()));
      if (!mounted) return;
      setState(() {
        _table = result.$1;
        _openOrders = result.$2;
        _servedOrderIds
          ..clear()
          ..addAll(served);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this table.'; _loading = false; });
    }
  }

  Future<void> _refreshSilently() async {
    try {
      final result = await _service.getDetail(widget.tableId);
      if (!mounted) return;

      // Keep the locally persisted served flags aligned with currently open
      // orders while updating the UI without showing a loading spinner.
      final activeIds = result.$2.map((o) => o.id).toSet();
      final served = Set<String>.from(_servedOrderIds)
        ..removeWhere((id) => !activeIds.contains(id));

      final changed = served.length != _servedOrderIds.length ||
          !served.containsAll(_servedOrderIds) ||
          !_servedOrderIds.containsAll(served);
      setState(() {
        _table = result.$1;
        _openOrders = result.$2;
        _servedOrderIds
          ..clear()
          ..addAll(served);
      });
      if (changed) await _persistServedState();
    } catch (_) {
      // Background refresh is best-effort. The visible Retry flow remains
      // responsible for surfaced network errors.
    }
  }

  Future<void> _markServed(Order order) async {
    if (_busyOrders.contains(order.id) || order.status != 'ready') return;
    setState(() => _busyOrders.add(order.id));
    try {
      _servedOrderIds.add(order.id);
      await _persistServedState();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #${order.orderNumber} marked as served. You can attend the next customer.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyOrders.remove(order.id));
    }
  }

  Future<void> _changeOrderItemQuantity(Order order, OrderItem item, int delta) async {
    if (_busyOrders.contains(order.id) || order.status != 'open') return;

    final nextItems = <CartItem>[];
    for (final current in order.items) {
      var quantity = current.quantity;
      if (current.productId == item.productId) {
        quantity += delta;
      }
      if (quantity > 0) {
        nextItems.add(
          CartItem(
            product: Product(
              id: current.productId,
              name: current.name,
              categoryId: '',
              sellingPrice: current.price,
              imageUrl: current.imageUrl,
            ),
            quantity: quantity,
          ),
        );
      }
    }

    setState(() => _busyOrders.add(order.id));
    try {
      final updated = await _orderService.updateOpenOrderItems(
        order.id,
        items: nextItems,
        discount: order.discount,
        notes: order.notes,
        customerId: order.customerId,
      );
      if (!mounted) return;
      final index = _openOrders.indexWhere((o) => o.id == order.id);
      if (index >= 0) {
        setState(() {
          final updatedOrders = List<Order>.from(_openOrders);
          updatedOrders[index] = updated;
          _openOrders = updatedOrders;
        });
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update quantity: $e')));
    } finally {
      if (mounted) setState(() => _busyOrders.remove(order.id));
    }
  }

  Future<void> _addCustomer() async {
    if (_starting) return;
    setState(() => _starting = true);

    try {
      // Create the table order first, then open the real food picker.
      // This intentionally avoids the standalone POS screen: the table
      // owns the order and AddItemsSheet owns item selection.
      final order = await _service.startOrder(
        widget.tableId,
        tableCustomerLabel: 'Customer ${_openOrders.length + 1}',
      );
      if (!mounted) return;

      final cart = context.read<CartProvider>();
      cart.clear();
      cart.configureContext(
        orderType: 'dine_in',
        tableId: widget.tableId,
        tableName: _table?.name,
        tableCustomerLabel: order.tableCustomerLabel,
        openOrderId: order.id,
      );

      // IMPORTANT: tapping Add New Order must immediately show the
      // product/category picker instead of opening a blank POS page.
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AddItemsSheet(),
      );

      if (!mounted) return;

      if (saved != true || cart.items.isEmpty) {
        // Do not leave an empty order behind if the user closes the picker.
        try {
          await _orderService.cancelOpenOrder(order.id);
        } catch (_) {}
        cart.clear();
        await _load();
        return;
      }

      setState(() => _busyOrders.add(order.id));
      try {
        await _orderService.updateOpenOrderItems(
          order.id,
          items: cart.items,
          discount: cart.discount,
          notes: cart.notes,
          customerId: cart.selectedCustomer?.id,
        );
      } finally {
        if (mounted) setState(() => _busyOrders.remove(order.id));
      }

      cart.clear();
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New order created. Add items or print KOT when ready.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start the order: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _addItemsToOrder(Order order) async {
    if (_busyOrders.contains(order.id)) return;

    final cart = context.read<CartProvider>();
    cart.clear();
    cart.configureContext(
      orderType: 'dine_in',
      tableId: widget.tableId,
      tableName: _table?.name,
      tableCustomerLabel: order.tableCustomerLabel,
      openOrderId: order.id,
    );
    cart.hydrateFromOpenOrder(
      items: order.items
          .map(
            (item) => CartItem(
              product: Product(
                id: item.productId,
                name: item.name,
                categoryId: '',
                sellingPrice: item.price,
                imageUrl: item.imageUrl,
              ),
              quantity: item.quantity,
            ),
          )
          .toList(),
      discount: order.discount,
    );
    cart.setNotes(order.notes ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddItemsSheet(),
    );

    if (!mounted) return;

    if (saved != true) {
      cart.clear();
      return;
    }

    setState(() => _busyOrders.add(order.id));
    try {
      // The table screen owns the open order, so closing the item picker
      // commits the current cart back to that same order. This avoids the
      // fragile Table -> POS -> Cart detour and makes the + button a true
      // "Add Food" action.
      await _orderService.updateOpenOrderItems(
        order.id,
        items: cart.items,
        discount: cart.discount,
        notes: cart.notes,
        customerId: cart.selectedCustomer?.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order items saved.')),
        );
      }
      cart.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save order items: $e')));
    } finally {
      if (mounted) setState(() => _busyOrders.remove(order.id));
    }
  }

  Future<void> _openOrder(Order order, {bool autoOpenCart = false}) async {
    context.read<CartProvider>().clear();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PosScreen(
          orderType: 'dine_in',
          tableId: widget.tableId,
          tableName: _table?.name,
          tableCustomerLabel: order.tableCustomerLabel,
          openOrderId: order.id,
          existingItems: order.items,
          existingDiscount: order.discount,
          autoOpenCart: autoOpenCart,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _updateCustomer(Order order) async {
    Customer? selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CustomerPickerSheet(),
    );
    if (selected == null || !mounted) return;
    try {
      await _orderService.updateOpenOrderCustomer(order.id, selected.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _shiftOrder(Order order) async {
    try {
      final tables = await _service.list();
      if (!mounted) return;

      final targets = tables
          .where((t) => t.id != widget.tableId)
          .toList()
        ..sort((a, b) {
          // Put available tables first, then occupied tables.
          final status = (a.isAvailable ? 0 : 1).compareTo(b.isAvailable ? 0 : 1);
          if (status != 0) return status;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other active tables are available.')),
        );
        return;
      }

      final target = await showModalBottomSheet<CafeTable>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _ShiftTableSheet(
          order: order,
          sourceTable: _table?.name ?? 'Current table',
          tables: targets,
        ),
      );

      if (target == null || !mounted) return;

      // Give the operator a final confirmation because this changes the
      // live table assignment of an unpaid order.
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm table shift'),
          content: Text(
            'Move order #${order.orderNumber} from ${_table?.name ?? 'this table'} to ${target.name}?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Shift Order')),
          ],
        ),
      );

      if (confirm != true || !mounted) return;
      setState(() => _busyOrders.add(order.id));
      await _orderService.shiftOrderToTable(order.id, target.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #${order.orderNumber} shifted to ${target.name}.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not shift order: $e')));
    } finally {
      if (mounted) setState(() => _busyOrders.remove(order.id));
    }
  }

  Future<void> _cancel(Order order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('Cancel unpaid order #${order.orderNumber}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Order')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _orderService.cancelOpenOrder(order.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _clearAll() async {
    if (_openOrders.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Orders'),
        content: Text('Cancel all ${_openOrders.length} active order(s) on ${_table?.name ?? 'this table'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Orders')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.clearAllOrders(widget.tableId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _rename() async {
    if (_table == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TableFormScreen(table: _table)),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _showQr() async {
    if (_table == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QrManagementScreen(focusTableId: widget.tableId)),
    );
  }

  Future<void> _printKot(Order order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var mode = prefs.getString(PrinterChoiceSheet.printModeKey);
      final printer = BluetoothPrinterService();
      await printer.refreshConnectionStatus();

      if (!printer.isConnected) {
        mode = await PrinterChoiceSheet.show(context);
        if (mode == null) return;
      }

      final settings = await SettingsService().get();
      bool printed;
      if (mode == PrinterChoiceSheet.bluetoothMode) {
        final width = prefs.getDouble('thermal_printer_width_mm') ?? 55;
        printed = await KotService().printViaBluetooth(order, settings, widthMm: width);
        if (!printed) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a printer for KOT')));
          return;
        }
      } else {
        // Browser printing was intentionally removed from the KOT workflow.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connect a Bluetooth thermal printer to print KOT.')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KOT printed. Order status was not changed.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not print KOT: $e')));
    }
  }

  Future<void> _printerChoice() async {
    await PrinterChoiceSheet.show(context);
    if (mounted) setState(() {});
  }

  // Closes the currently open bottom-sheet menu, then runs [next] on the
  // following frame. Calling `_updateCustomer`/`_shiftOrder`/etc directly
  // after `Navigator.pop(ctx)` reopens a new modal (Provider-backed sheet or
  // dialog) while the popped sheet's element is still detaching, which can
  // trip Flutter's InheritedElement `_dependents.isEmpty` assertion. The
  // parent screen (this State) always owns the follow-up navigation and
  // waits a frame so the old sheet is fully torn down first.
  void _closeMenuThen(BuildContext ctx, FutureOr<void> Function() next) {
    Navigator.pop(ctx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) next();
    });
  }

  Future<void> _menu(Order order) async {
    final canManage = context.read<AuthProvider>().currentUser?.canManageTables ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_outline),
              title: const Text('Update Customer Info'),
              onTap: () => _closeMenuThen(ctx, () => _updateCustomer(order)),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz),
              title: const Text('Shift to Table'),
              onTap: () => _closeMenuThen(ctx, () => _shiftOrder(order)),
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined),
              title: const Text('Cancel Order'),
              onTap: () => _closeMenuThen(ctx, () => _cancel(order)),
            ),
            if (canManage)
              ListTile(
                leading: Icon(Icons.qr_code_2),
                title: const Text('Show QR Code'),
                onTap: () => _closeMenuThen(ctx, _showQr),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _tableMenu() async {
    final canManage = context.read<AuthProvider>().currentUser?.canManageTables ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage)
              ListTile(
                leading: Icon(Icons.qr_code_2),
                title: const Text('Show QR Code'),
                onTap: () => _closeMenuThen(ctx, _showQr),
              ),
            if (_openOrders.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_sweep_outlined),
                title: const Text('Clear All Orders'),
                onTap: () => _closeMenuThen(ctx, _clearAll),
              ),
            if (canManage)
              ListTile(
                leading: Icon(Icons.edit_outlined),
                title: const Text('Rename Table'),
                onTap: () => _closeMenuThen(ctx, _rename),
              ),
            if (canManage)
              ListTile(
                leading: Icon(Icons.delete_outline),
                title: const Text('Delete Table'),
                onTap: () => _closeMenuThen(ctx, () async {
                  try {
                    await _service.delete(widget.tableId);
                    if (mounted) Navigator.pop(context, true);
                  } on ApiException catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }

  int get _flowStep {
    if (_openOrders.isEmpty) return 0;
    final activeUnserved = _openOrders.where((o) => !_servedOrderIds.contains(o.id)).toList();
    if (activeUnserved.isNotEmpty) return 0;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final table = _table;
    return Scaffold(
      appBar: AppBar(
        title: Text(table?.name ?? 'Table'),
        actions: [
          AnimatedBuilder(
            animation: BluetoothPrinterService(),
            builder: (context, _) {
              final printer = BluetoothPrinterService();
              return TextButton.icon(
                onPressed: _printerChoice,
                icon: Icon(Icons.print_outlined, size: 20),
                label: Text(printer.isConnected ? (printer.connectedName ?? 'Printer') : 'No Printer'),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
          ),
          IconButton(icon: Icon(Icons.more_vert), onPressed: _tableMenu),
          IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ],
      ),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 110),
                    children: [
                      OrderFlowStepper(currentStep: _flowStep, tableServiceFlow: true),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        child: Row(
                          children: [
                            const Text('Open orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('${_openOrders.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (_openOrders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 24),
                          child: Column(
                            children: [
                              Icon(Icons.table_restaurant_outlined, size: 56, color: AppColors.textMuted),
                              const SizedBox(height: 14),
                              const Text('This table is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 7),
                              Text('Add a customer to start a new order.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                        )
                      else
                        ..._openOrders.map((order) => _OrderCard(
                              order: order,
                              onOpen: () => _addItemsToOrder(order),
                              onCheckout: () => _openOrder(order, autoOpenCart: true),
                              onMenu: () => _menu(order),
                              onPrintKot: () => _printKot(order),
                              onShift: () => _shiftOrder(order),
                              onChangeQuantity: (item, delta) => _changeOrderItemQuantity(order, item, delta),
                              isServed: _servedOrderIds.contains(order.id),
                              busy: _busyOrders.contains(order.id),
                            )),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _starting ? null : _addCustomer,
                            icon: _starting
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.add_circle_outline),
                            label: Text(
                              _openOrders.isNotEmpty && _servedItems == _totalItems
                                  ? 'Add New Order'
                                  : 'Add New Order',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: null,
    );
  }
}

class _ShiftTableSheet extends StatelessWidget {
  final Order order;
  final String sourceTable;
  final List<CafeTable> tables;

  const _ShiftTableSheet({
    required this.order,
    required this.sourceTable,
    required this.tables,
  });

  @override
  Widget build(BuildContext context) {
    final available = tables.where((t) => t.isAvailable).toList();
    final occupied = tables.where((t) => !t.isAvailable).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(
                  'Shift Order #${order.orderNumber}',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Text(
                  'Move from $sourceTable to another dining table. Choose an available table, or an occupied table to keep multiple customer orders together.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
              ),
              if (available.isNotEmpty) ...[
                _sectionLabel('Available tables'),
                ...available.map((t) => _tableTile(context, t)),
              ],
              if (occupied.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionLabel('Occupied / Reserved tables'),
                ...occupied.map((t) => _tableTile(context, t)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
        ),
      );

  Widget _tableTile(BuildContext context, CafeTable table) {
    final occupied = table.isOccupied;
    final reserved = table.isReserved;
    final status = reserved
        ? 'Reserved'
        : occupied
            ? '${table.openOrderCount} open order${table.openOrderCount == 1 ? '' : 's'}'
            : 'Available';

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(Icons.table_restaurant_outlined, color: AppColors.primary),
        ),
        title: Text(table.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$status • ${table.capacity} seats'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pop(context, table),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderService _orderService = OrderService();
  final Order order;
  final VoidCallback onOpen;
  final VoidCallback onCheckout;
  final VoidCallback onMenu;
  final VoidCallback onPrintKot;
  final VoidCallback onShift;
  final void Function(OrderItem item, int delta) onChangeQuantity;
  final bool isServed;
  final bool busy;

  _OrderCard({
    required this.order,
    required this.onOpen,
    required this.onCheckout,
    required this.onMenu,
    required this.onPrintKot,
    required this.onShift,
    required this.onChangeQuantity,
    required this.isServed,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bill No: #${order.orderNumber}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        '${Formatters.time(order.createdAt)} • $itemCount/${itemCount == 0 ? 0 : itemCount} Items',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isServed
                              ? AppColors.success.withValues(alpha: .10)
                              : order.status == 'ready'
                                  ? AppColors.primaryLight
                                  : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isServed
                              ? 'Served'
                              : 'Order in progress',
                          style: TextStyle(
                            color: isServed ? AppColors.success : AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: order.status == 'open' ? 'Add items' : 'Order is completed',
                  onPressed: busy || order.status != 'open' ? null : onOpen,
                  icon: Icon(Icons.add_circle_outline, color: AppColors.primary, size: 30),
                ),
                IconButton(
                  tooltip: 'Order options',
                  onPressed: onMenu,
                  icon: Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  ProductImage(
                    name: item.name,
                    imageUrl: item.imageUrl,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          '${Formatters.currency(item.price)} • ${order.orderType == 'dine_in' ? 'Dine-in' : order.orderType}',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Decrease quantity',
                          onPressed: busy || order.status != 'open'
                              ? null
                              : () => onChangeQuantity(item, -1),
                          icon: const Icon(Icons.remove, size: 19),
                          color: AppColors.primary,
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Increase quantity',
                          onPressed: busy || order.status != 'open'
                              ? null
                              : () => onChangeQuantity(item, 1),
                          icon: const Icon(Icons.add, size: 19),
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (order.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No items yet', style: TextStyle(color: AppColors.textMuted)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              children: [
                TextField(
                  controller: TextEditingController(text: order.notes ?? ''),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.edit_note),
                    hintText: 'Add any special instructions for this order...',
                  ),
                  onSubmitted: (value) async {
                    try {
                      await _orderService.updateOpenOrderNotes(order.id, value);
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                _summaryRow('Sub Total', Formatters.currency(order.subtotal), bold: true),
                _summaryRow('CGST + SGST', Formatters.currency(order.tax)),
                if (order.discount > 0) _summaryRow('Discount', '-${Formatters.currency(order.discount)}'),
                const Divider(height: 20),
                _summaryRow('Total', Formatters.currency(order.grandTotal), bold: true, primary: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onShift,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Shift Table'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy || order.items.isEmpty ? null : onPrintKot,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print KOT'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // KDS has been removed from the staff app. An open table
                // order can go directly to billing; there is no kitchen gate.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: busy || order.items.isEmpty ? null : onCheckout,
                    icon: const Icon(Icons.credit_card_outlined),
                    label: const Text('Checkout / Bill'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, bool primary = false}) {
    final style = TextStyle(
      fontSize: bold ? 17 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: primary ? AppColors.primary : AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
