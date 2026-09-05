import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../models/misc_models.dart';
import '../../services/order_service.dart';
import '../../services/misc_services.dart';
import '../../services/receipt_service.dart';
import '../pos/bill_success_screen.dart';
import '../../providers/auth_provider.dart';
import 'qr_checkout_sheet.dart';
import '../../providers/connectivity_provider.dart';
import '../settings/printer_settings_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  OrderDetailScreen({
    super.key,
    required this.orderId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> with WidgetsBindingObserver {
  final _orderService = OrderService();
  final _receiptService = ReceiptService();

  Order? _order;
  BusinessSettings _settings = BusinessSettings();

  bool _loading = true;
  String? _error;
  bool _busy = false;

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

  Future<void> _runReceiptAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not print/share the receipt. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printOnThermalPrinter(Order order) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final widthMm = prefs.getDouble('thermal_printer_width_mm') ?? 80;
      final ok = await _receiptService.printViaBluetooth(order, _settings, widthMm: widthMm);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No printer connected.'),
            action: SnackBarAction(
              label: 'Connect',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrinterSettingsScreen())),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not print the receipt. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _orderService.getById(widget.orderId),
        SettingsService().get(),
      ]);

      setState(() {
        _order = results[0] as Order;
        _settings = results[1] as BusinessSettings;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load this order.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateQrStatus(String nextStatus) async {
    if (_order == null || !_order!.isQrOrder) return;

    setState(() => _busy = true);

    try {
      await _orderService.updateQrStatus(
        widget.orderId,
        nextStatus,
      );

      await _load();

      if (mounted) {
        final label = nextStatus == 'preparing'
            ? 'Order accepted — preparing'
            : 'Order marked ready';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(label)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openQrCheckout() async {
    final order = _order;
    if (order == null || order.status == 'completed' || order.status == 'voided') return;

    final updated = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QrCheckoutSheet(order: order),
    );

    if (updated == null || !mounted) return;
    setState(() => _order = updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill completed and payment recorded.')));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BillSuccessScreen(order: updated)));
    }
  }

  Future<void> _voidOrder() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Void this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will restock inventory and reverse any UDHAR effect. '
              'This cannot be undone.',
            ),
            SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Void Order',
              style: TextStyle(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _busy = true);

    try {
      await _orderService.voidOrder(
        widget.orderId,
        reason: reasonController.text.trim(),
      );

      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      reasonController.dispose();

      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.isAdmin;
    // AuthProvider exposes isAdmin, while manager status
    // belongs to the currently authenticated User.

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _order != null
              ? 'Bill #${_order!.orderNumber}'
              : 'Order',
        ),
        actions: [
          if (_order != null && _order!.status == 'completed') ...[
            TextButton.icon(
              icon: Icon(Icons.print, size: 22),
              label: const Text('Print'),
              onPressed: _busy ? null : () => _printOnThermalPrinter(_order!),
            ),
            IconButton(
              icon: Icon(Icons.share_outlined),
              onPressed: _busy
                  ? null
                  : () => _runReceiptAction(
                        () => _receiptService.shareReceipt(
                          _order!,
                          _settings,
                        ),
                      ),
            ),
            if (isAdmin)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: AppColors.danger,
                ),
                onPressed: _busy ? null : _voidOrder,
              ),
          ],
        ],
      ),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(
                  message: _error!,
                  onRetry: _load,
                )
              : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final order = _order!;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _paymentSummary(order),

        if (order.isQrOrder &&
            order.status != 'completed' &&
            order.status != 'voided')
          Container(
            margin: EdgeInsets.only(bottom: 14),
            padding: EdgeInsets.all(14),
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
                Text(
                  'QR ORDER WORKFLOW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _qrStatusLabel(order.status),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (order.status == 'open')
                      ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _updateQrStatus(
                                  'preparing',
                                ),
                        icon: Icon(
                          Icons.play_arrow,
                          size: 18,
                        ),
                        label: Text('Accept'),
                      )
                    else if (order.status == 'preparing')
                      ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _updateQrStatus(
                                  'ready',
                                ),
                        icon: Icon(
                          Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: Text('Mark Ready'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _busy ? null : _openQrCheckout,
                        icon: Icon(Icons.receipt_long, size: 18),
                        label: Text('Checkout'),
                      ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Customer sees this status automatically on the QR menu.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

        if (order.status == 'voided')
          Container(
            margin: EdgeInsets.only(bottom: 14),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.block,
                  color: AppColors.danger,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'This order has been voided',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        if (order.isQrOrder)
          Container(
            margin: EdgeInsets.only(bottom: 14),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.qr_code_2,
                  color: AppColors.primaryDark,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  order.staffName == null
                      ? 'Placed by customer via QR menu · awaiting staff'
                      : 'Placed by customer via QR menu',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        Container(
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
              Text(
                Formatters.dateTime(order.createdAt),
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              Text(
                order.orderType == 'dine_in'
                    ? 'Dine-In'
                      '${order.tableName != null ? ' · ${order.tableName}' : ''}'
                      '${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                    : (order.orderType == 'delivery'
                        ? 'Delivery'
                        : 'Takeaway'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              if (order.staffName != null)
                Text(
                  'Attended by: ${order.staffName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

              if (order.customerName != null)
                Text(
                  'Customer: ${order.customerName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

              if (order.qrCustomerContact?.name != null)
                Text(
                  'Customer: ${order.qrCustomerContact!.name}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

              if (order.qrCustomerContact?.phone != null)
                Text(
                  'Phone: ${order.qrCustomerContact!.phone}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

              Divider(height: 24),

              ...order.items.map(
                (item) => Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.name}  x${item.quantity}',
                        ),
                      ),
                      Text(
                        Formatters.currency(item.total),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Divider(height: 24),

              _row(
                'Subtotal',
                Formatters.currency(order.subtotal),
              ),

              if (order.discount > 0)
                _row(
                  'Discount',
                  '- ${Formatters.currency(order.discount)}',
                ),

              if (order.tax > 0)
                _row(
                  'Tax',
                  Formatters.currency(order.tax),
                ),

              Divider(height: 20),

              _row(
                'Grand Total',
                Formatters.currency(order.grandTotal),
                bold: true,
              ),

              SizedBox(height: 12),

              _row(
                'Payment Method',
                order.paymentMethod,
              ),

              if (order.paymentMethod == 'CASH' &&
                  order.amountReceived != null) ...[
                _row(
                  'Amount Received',
                  Formatters.currency(
                    order.amountReceived!,
                  ),
                ),
                _row(
                  'Change Returned',
                  Formatters.currency(
                    order.changeReturned,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _qrStatusLabel(String status) {
    switch (status) {
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for customer';
      case 'completed':
        return 'Completed';
      case 'voided':
        return 'Cancelled';
      default:
        return 'New QR order';
    }
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 16 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: bold ? 17 : 14,
              color: bold
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
  Widget _paymentSummary(Order order) {
    final paid = order.paymentStatus == 'paid';
    final color = paid ? AppColors.success : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .30))),
      child: Row(children: [
        Icon(paid ? Icons.verified : Icons.pending_actions, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(paid ? 'PAYMENT PAID' : 'PAYMENT PENDING', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
          const SizedBox(height: 2),
          Text(order.paymentMethod == 'UPI' && !paid ? 'Verify UPI reference / UTR before checkout.' : '${order.paymentMethod} • ${order.grandTotal.toStringAsFixed(2)}'),
          if (order.upiReference?.trim().isNotEmpty == true) Text('UTR: ${order.upiReference}', style: const TextStyle(fontSize: 12)),
        ])),
      ]),
    );
  }

}
