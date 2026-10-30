import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/pos_ui.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../models/misc_models.dart';
import '../../services/order_service.dart';
import '../../services/misc_services.dart';
import '../../services/receipt_service.dart';
import '../pos/bill_success_screen.dart';
import 'open_bill.dart';
import 'qr_checkout_sheet.dart';
import '../../providers/connectivity_provider.dart';
import '../settings/printer_settings_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({
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
      final widthMm = prefs.getDouble('thermal_printer_width_mm') ?? 55;
      final ok = await _receiptService.printViaBluetooth(order, _settings, widthMm: widthMm);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No printer connected.'),
            action: SnackBarAction(
              label: 'Connect',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
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

      if (!mounted) return;
      setState(() {
        _order = results[0] as Order;
        _settings = results[1] as BusinessSettings;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this order.');
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

  @override
  Widget build(BuildContext context) {
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
              icon: const Icon(Icons.print, size: 22),
              label: const Text('Print'),
              onPressed: _busy ? null : () => _printOnThermalPrinter(_order!),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: _busy
                  ? null
                  : () => _runReceiptAction(
                        () => _receiptService.shareReceipt(
                          _order!,
                          _settings,
                        ),
                      ),
            ),
          ],
        ],
      ),
      body: _loading
          ? const LoadingState()
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _orderHeader(order),
        const SizedBox(height: 14),

        if (order.isQrOrder &&
            order.status != 'completed' &&
            order.status != 'voided')
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
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
                const Text(
                  'QR ORDER WORKFLOW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _qrStatusLabel(order.status),
                        style: const TextStyle(
                          fontSize: 14,
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
                        icon: const Icon(
                          Icons.play_arrow,
                          size: 18,
                        ),
                        label: const Text('Accept'),
                      )
                    else if (order.status == 'preparing')
                      ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _updateQrStatus(
                                  'ready',
                                ),
                        icon: const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: const Text('Mark Ready'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _busy ? null : _openQrCheckout,
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('Checkout'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Customer sees this status automatically on the QR menu.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

        if (order.status == 'voided')
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
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
                const SizedBox(width: 8),
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
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
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
                const SizedBox(width: 8),
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
          padding: const EdgeInsets.all(16),
          decoration: FreshUi.card(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Transaction Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Items', style: _headStyle)),
                  SizedBox(width: 40, child: Text('Qty', textAlign: TextAlign.center, style: _headStyle)),
                  SizedBox(width: 80, child: Text('Price', textAlign: TextAlign.right, style: _headStyle)),
                ],
              ),
              Divider(height: 18, color: AppColors.border),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            if (item.note != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: StatusPill(label: item.note!, color: AppColors.warning, icon: Icons.edit_note_rounded),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${item.quantity}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      SizedBox(
                        width: 80,
                        child: Text(Formatters.currency(item.total), textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 24, color: AppColors.border),
              _row('Items (${order.items.fold<int>(0, (n, i) => n + i.quantity)})', Formatters.currency(order.subtotal)),
              // Discount, charges, GST per rate and round-off.
              if (order.bill.taxes.isNotEmpty || order.bill.hasCharges || order.bill.roundOff != 0 || order.bill.complimentary)
                for (final row in order.bill.rows())
                  _row(
                    row.$1,
                    row.$2 < 0 ? '- ${Formatters.currency(-row.$2)}' : Formatters.currency(row.$2),
                  )
              else ...[
                if (order.discount > 0) _row('Discount', '- ${Formatters.currency(order.discount)}'),
                if (order.tax > 0) _row('Tax', Formatters.currency(order.tax)),
              ],
              Divider(height: 24, color: AppColors.border),
              _row('Total', Formatters.currency(order.grandTotal), bold: true),
              if (order.paymentStatus == 'paid' || order.status == 'completed') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      _row('Paid by', ReceiptService.paymentLabel(order)),
                      if (order.onlineOrderRef != null) _row('App order ID', order.onlineOrderRef!),
                      if (order.cardReference != null) _row('Card ref', order.cardReference!),
                      if (order.upiReference?.trim().isNotEmpty == true) _row('UTR', order.upiReference!),
                      if (order.paymentMethod == 'CASH' && order.amountReceived != null) ...[
                        _row('Amount received', Formatters.currency(order.amountReceived!)),
                        _row('Change returned', Formatters.currency(order.changeReturned)),
                      ],
                    ],
                  ),
                ),
              ],
              if (!order.isQrOrder && order.paymentStatus != 'paid' && const ['open', 'preparing', 'ready'].contains(order.status)) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await openBill(context, order);
                      if (mounted) _load();
                    },
                    icon: const Icon(Icons.payments_rounded),
                    label: Text('Pay Bill  •  ${Formatters.currency(order.grandTotal)}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  TextStyle get _headStyle => TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted);

  /// Code badge, customer, bill number / type, and status pills.
  Widget _orderHeader(Order order) {
    final paid = order.paymentStatus == 'paid' || order.status == 'completed';
    final voided = order.status == 'voided';
    final label = order.tableCustomerLabel?.trim() ?? '';
    final slot = RegExp(r'^([TD]\d+)').firstMatch(label)?.group(1);
    final code = order.orderType != 'dine_in' && slot != null
        ? slot
        : order.tableNumber != null
            ? 'T${order.tableNumber}'
            : '#${order.orderNumber}';
    final type = order.orderType == 'dine_in'
        ? 'Dine In${order.tableName != null ? ' · ${order.tableName}' : ''}'
        : order.orderType == 'delivery'
            ? 'Delivery'
            : 'Takeaway';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: FreshUi.card(radius: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CodeBadge(code: code, color: AppColors.primary, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.printCustomerName ?? 'Walk-in customer', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('#${order.orderNumber} / $type', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  '${Formatters.dateTime(order.createdAt)}${order.staffName != null ? ' · ${order.staffName}' : ''}',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                if (order.invoiceNumber != null) ...[
                  const SizedBox(height: 2),
                  Text('Invoice ${order.invoiceNumber}', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (voided)
                StatusPill(label: 'Cancelled', color: AppColors.danger, icon: Icons.block)
              else if (order.status == 'completed')
                StatusPill(label: 'Completed', color: AppColors.success, icon: Icons.check_circle_rounded)
              else
                StatusPill(label: 'Running', color: AppColors.info, icon: Icons.timelapse_rounded),
              const SizedBox(height: 6),
              if (!voided)
                paid
                    ? StatusPill(label: 'Paid', color: AppColors.success)
                    : StatusPill(label: 'Waiting for payment', color: AppColors.warning),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 15 : 12.5,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: bold ? 18 : 12.5,
              color: bold
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

}
