import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});
  @override State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> with WidgetsBindingObserver {
  final _service = OrderService();
  List<Order> _orders = [];
  Timer? _timer;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
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
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  void _handleConnectivityChange() {
    final online = _connectivity?.isOnline ?? true;
    if (online && !_wasOnline) _load();
    _wasOnline = online;
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent && mounted) setState(() => _refreshing = true);
    try {
      final orders = await _service.kitchenOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; _refreshing = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load kitchen orders.'; _loading = false; _refreshing = false; });
    }
  }

  Future<void> _advance(Order order) async {
    final next = order.status == 'open' ? 'preparing' : 'ready';
    try {
      await _service.updateQrStatus(order.id, next);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update kitchen status.')));
    }
  }

  Future<void> _cancel(Order order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('Cancel order #${order.orderNumber}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Order')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.cancelOpenOrder(order.id, reason: 'Cancelled from Kitchen Display');
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not cancel the order.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final newOrders = _orders.where((o) => o.status == 'open').toList();
    final preparing = _orders.where((o) => o.status == 'preparing').toList();
    final ready = _orders.where((o) => o.status == 'ready').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Display'),
        actions: [
          if (_refreshing) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(onPressed: _refreshing ? null : () => _load(), icon: const Icon(Icons.refresh), tooltip: 'Refresh kitchen'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _orders.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    children: [
                      if (_error != null) _errorBanner(),
                      _queueHeader(newOrders.length, preparing.length, ready.length),
                      if (newOrders.isNotEmpty) _section('NEW — ACCEPT ORDER', newOrders),
                      if (preparing.isNotEmpty) _section('PREPARING', preparing),
                      if (ready.isNotEmpty) _section('READY — BILL / SERVE', ready),
                      if (_orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No active kitchen orders.'))),
                    ],
                  ),
                ),
    );
  }

  Widget _errorBanner() => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [const Icon(Icons.wifi_off, size: 18), const SizedBox(width: 8), Expanded(child: Text(_error!)), TextButton(onPressed: _load, child: const Text('Retry'))]),
  );

  Widget _queueHeader(int n, int p, int r) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [_count('NEW', n, AppColors.warning), _count('COOKING', p, AppColors.info), _count('READY', r, AppColors.success)]),
    ),
  );

  Widget _count(String label, int value, Color color) => Expanded(
    child: Column(children: [Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))]),
  );

  Widget _section(String title, List<Order> orders) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)), const SizedBox(width: 8), Text('${orders.length}', style: TextStyle(color: AppColors.textMuted))])),
      ...orders.map(_orderCard),
      const SizedBox(height: 14),
    ],
  );

  Widget _orderCard(Order order) {
    final isNew = order.status == 'open';
    final isReady = order.status == 'ready';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isNew ? 2 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text('#${order.orderNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(width: 8), _statusChip(_statusText(order.status), _statusColor(order.status)), const Spacer(), Text(order.tableName ?? 'Dine-in', style: const TextStyle(fontWeight: FontWeight.w700))]),
            if (order.qrCustomerContact?.name?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text(order.qrCustomerContact!.name!, style: TextStyle(color: AppColors.textSecondary))),
            const Divider(height: 18),
            ...order.items.map((i) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Text('${i.quantity}×', style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(width: 10), Expanded(child: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)))]))),
            if (order.notes?.trim().isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Note: ${order.notes}', style: const TextStyle(fontStyle: FontStyle.italic))),
            const SizedBox(height: 10),
            Row(children: [
              _paymentChip(order),
              const Spacer(),
              if (!isReady) ...[
                TextButton(onPressed: () => _cancel(order), child: Text('Cancel', style: TextStyle(color: AppColors.danger))),
                const SizedBox(width: 4),
                FilledButton.icon(onPressed: () => _advance(order), icon: Icon(isNew ? Icons.play_arrow : Icons.check, size: 18), label: Text(isNew ? 'Accept & Prepare' : 'Mark Ready')),
              ] else
                OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))), icon: const Icon(Icons.receipt_long, size: 18), label: const Text('Open Bill')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _paymentChip(Order order) {
    // Payment is intentionally NOT shown as a kitchen status. A QR order may
    // be cash-due or waiting for payment verification while the food is
    // already being prepared. Billing/checkout owns payment settlement.
    final isUpi = order.paymentMethod == 'UPI';
    final color = isUpi ? AppColors.info : AppColors.textMuted;
    final text = isUpi ? 'UPI' : (order.paymentMethod == 'CASH' ? 'CASH' : order.paymentMethod);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isUpi ? Icons.account_balance_wallet_outlined : Icons.payments_outlined, size: 15, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );
  }

  Widget _statusChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
  );

  String _statusText(String status) => switch (status) {
    'open' => 'NEW',
    'preparing' => 'PREPARING',
    'ready' => 'READY',
    _ => status.toUpperCase(),
  };

  Color _statusColor(String status) => switch (status) {
    'open' => AppColors.warning,
    'preparing' => AppColors.info,
    'ready' => AppColors.success,
    _ => AppColors.textMuted,
  };
}
