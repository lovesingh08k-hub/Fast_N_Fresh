import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/table.dart';
import '../../models/order.dart';
import '../../services/table_service.dart';
import '../../services/order_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../pos/pos_screen.dart';

/// Shows every currently-open unpaid customer/order on this table.
///
/// Each customer/order remains completely separate:
/// - Separate cart
/// - Separate order
/// - Separate bill
/// - Separate payment
///
/// This allows multiple simultaneous customers on one table.
class TableDetailScreen extends StatefulWidget {
  final String tableId;

  TableDetailScreen({
    super.key,
    required this.tableId,
  });

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
  final Set<String> _cancellingIds = {};

  String? _error;

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && mounted && _error != null) {
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

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.getDetail(widget.tableId);

      if (!mounted) return;

      setState(() {
        _table = result.$1;
        _openOrders = result.$2;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load this table.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addCustomer() async {
    if (_starting) return;

    setState(() {
      _starting = true;
    });

    try {
      final order = await _service.startOrder(
        widget.tableId,
        tableCustomerLabel:
            'Customer ${_openOrders.length + 1}',
      );

      if (!mounted) return;

      // Start with a fresh cart for this customer.
      context.read<CartProvider>().clear();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PosScreen(
            orderType: 'dine_in',
            tableId: widget.tableId,
            tableName: _table?.name,
            tableCustomerLabel: order.tableCustomerLabel,
            openOrderId: order.id,
          ),
        ),
      );

      if (mounted) {
        await _load();
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start a new customer order.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  Future<void> _openExisting(
    Order order, {
    bool autoOpenCart = false,
  }) async {
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

    if (mounted) {
      await _load();
    }
  }

  Future<void> _cancelOrder(Order order) async {
    if (_cancellingIds.contains(order.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel this order?'),
        content: Text(
          'This will cancel the unpaid order for '
          '${order.tableCustomerLabel ?? 'this customer'}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _cancellingIds.add(order.id);
    });

    try {
      await _orderService.cancelOpenOrder(order.id);

      if (mounted) {
        await _load();
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel this order.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancellingIds.remove(order.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManageTables =
        context.watch<AuthProvider>().currentUser?.canManageTables ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _table?.name ?? 'Table',
        ),
      ),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(16),
                    children: [
                      if (_openOrders.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 40,
                          ),
                          child: Center(
                            child: Text(
                              'This table is empty.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._openOrders.map(
                          (order) => _CustomerOrderCard(
                            order: order,
                            onOpen: () => _openExisting(order),
                            onBill: () => _openExisting(
                              order,
                              autoOpenCart: true,
                            ),
                            onCancel: canManageTables
                                ? () => _cancelOrder(order)
                                : null,
                            cancelling:
                                _cancellingIds.contains(order.id),
                          ),
                        ),

                      SizedBox(height: 12),

                      OutlinedButton.icon(
                        onPressed:
                            _starting ? null : _addCustomer,
                        icon: _starting
                            ? SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.person_add_alt,
                                size: 18,
                              ),
                        label: Text(
                          'Add Customer',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onOpen;
  final VoidCallback onBill;
  final VoidCallback? onCancel;
  final bool cancelling;

  _CustomerOrderCard({
    required this.order,
    required this.onOpen,
    required this.onBill,
    this.onCancel,
    this.cancelling = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        bottom: 12,
      ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  order.tableCustomerLabel ??
                      'Customer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                Formatters.currency(
                  order.grandTotal,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),

          SizedBox(height: 4),

          Text(
            order.items.isEmpty
                ? 'No items yet'
                : order.items
                    .map(
                      (item) =>
                          '${item.quantity}x ${item.name}',
                    )
                    .join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                Theme.of(context).textTheme.bodyMedium,
          ),

          if (order.staffName != null) ...[
            SizedBox(height: 4),
            Text(
              'Attended by: ${order.staffName}',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],

          SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: Text(
                    'Open Order',
                  ),
                ),
              ),

              SizedBox(width: 10),

              Expanded(
                child: ElevatedButton(
                  onPressed: onBill,
                  child: Text(
                    'Bill',
                  ),
                ),
              ),
            ],
          ),

          if (onCancel != null) ...[
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: cancelling ? null : onCancel,
                icon: cancelling
                    ? SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.delete_outline, size: 16),
                label: Text(
                  cancelling ? 'Cancelling...' : 'Cancel Order',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}