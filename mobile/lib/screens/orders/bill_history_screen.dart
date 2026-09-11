import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';

/// Manager-facing bill register. This is deliberately separate from the
/// operational Orders/Table screen: Orders is for work-in-progress, while
/// Bills is the permanent sales register for completed customer bills.
class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  final _service = OrderService();
  final _search = TextEditingController();

  List<Order> _bills = [];
  bool _loading = true;
  String? _error;
  String _period = 'Today';
  String? _type;
  String? _payment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? get _from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'Today': return today;
      case 'Yesterday': return today.subtract(const Duration(days: 1));
      case 'This Week': return today.subtract(Duration(days: today.weekday - 1));
      case 'This Month': return DateTime(today.year, today.month, 1);
      case 'All': return null;
      default: return today;
    }
  }

  DateTime? get _to {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime end(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    switch (_period) {
      case 'Today': return end(today);
      case 'Yesterday': return end(today.subtract(const Duration(days: 1)));
      case 'This Week': return end(today.add(Duration(days: 7 - today.weekday)));
      case 'This Month':
        final next = today.month == 12 ? DateTime(today.year + 1, 1, 1) : DateTime(today.year, today.month + 1, 1);
        return end(next.subtract(const Duration(days: 1)));
      case 'All': return null;
      default: return end(today);
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Bills is the billing register, not only the paid-sales register.
      // Include active/unpaid bills as well as completed bills so a bill that
      // is awaiting payment is never invisible to the cashier/manager.
      // Voided orders are excluded because they are not payable bills.
      final bills = await _service.list(
        from: _from,
        to: _to,
        paymentMethod: _payment,
        orderType: _type,
        search: _search.text,
        limit: 100,
      );
      if (!mounted) return;
      setState(() => _bills = bills
          .where((o) => o.status != 'voided')
          .toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load bills.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'dine_in': return 'Dine In';
      case 'takeaway': return 'Takeaway';
      case 'delivery': return 'Delivery';
      default: return 'All';
    }
  }

  String _paymentLabel(String? method) => method == null ? 'All payments' : method;

  @override
  Widget build(BuildContext context) {
    final total = _bills.fold<double>(0, (sum, o) => sum + o.grandTotal);
    final paid = _bills.where((o) => o.paymentStatus == 'paid' || o.status == 'completed').fold<double>(0, (sum, o) => sum + o.grandTotal);
    final pending = _bills.where((o) => o.paymentStatus != 'paid' && o.status != 'completed').fold<double>(0, (sum, o) => sum + o.grandTotal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 22),
          children: [
            _summary(
              total,
              paid: _bills.where((o) => o.paymentStatus == 'paid' || o.status == 'completed').fold<double>(0, (sum, o) => sum + o.grandTotal),
              pending: _bills.where((o) => o.paymentStatus != 'paid' && o.status != 'completed').fold<double>(0, (sum, o) => sum + o.grandTotal),
            ),
            const SizedBox(height: 14),
            _searchBox(),
            const SizedBox(height: 10),
            _filters(),
            const SizedBox(height: 14),
            if (_error != null) InlineRetryBanner(message: _error!, onRetry: _load),
            if (_loading && _bills.isEmpty)
              const SectionLoadingBox(height: 220)
            else if (!_loading && _bills.isEmpty)
              _emptyState()
            else
              ..._bills.map(_billCard),
          ],
        ),
      ),
    );
  }

  Widget _summary(double total, {required double paid, required double pending}) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sales Register', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(Formatters.currency(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${_bills.length} bill${_bills.length == 1 ? '' : 's'} · $_period', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (pending > 0) ...[
              const SizedBox(height: 3),
              Text('Paid ${Formatters.currency(paid)} · Pending ${Formatters.currency(pending)}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ],
          ])),
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long_rounded, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _load(),
      decoration: InputDecoration(
        hintText: 'Search bill no, customer or phone',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); _load(); setState(() {}); }, icon: const Icon(Icons.close_rounded)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _filterChip(_period, () => _periodSheet()),
        const SizedBox(width: 8),
        _filterChip(_typeLabel(_type), () => _typeSheet()),
        const SizedBox(width: 8),
        _filterChip(_paymentLabel(_payment), () => _paymentSheet()),
      ]),
    );
  }

  Widget _filterChip(String label, VoidCallback onTap) => ActionChip(
    avatar: const Icon(Icons.tune_rounded, size: 16),
    label: Text(label),
    onPressed: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
  );

  Future<void> _periodSheet() async {
    final value = await _pick(['Today', 'Yesterday', 'This Week', 'This Month', 'All'], _period, 'Bill period');
    if (value != null) { setState(() => _period = value); _load(); }
  }

  Future<void> _typeSheet() async {
    final value = await _pick(['All', 'Dine In', 'Takeaway', 'Delivery'], _typeLabel(_type), 'Order type');
    if (value != null) { setState(() => _type = value == 'All' ? null : {'Dine In': 'dine_in', 'Takeaway': 'takeaway', 'Delivery': 'delivery'}[value]); _load(); }
  }

  Future<void> _paymentSheet() async {
    final value = await _pick(['All', 'CASH', 'UPI', 'CREDIT', 'MIXED'], _payment ?? 'All', 'Payment method');
    if (value != null) { setState(() => _payment = value == 'All' ? null : value); _load(); }
  }

  Future<String?> _pick(List<String> options, String selected, String title) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 10), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
        ...options.map((option) => ListTile(title: Text(option), trailing: option == selected ? Icon(Icons.check_rounded, color: AppColors.primary) : null, onTap: () => Navigator.pop(context, option))),
        const SizedBox(height: 8),
      ])),
    );
  }

  Widget _billCard(Order order) {
    final customer = order.customerName ?? order.qrCustomerContact?.name ?? 'Walk-in customer';
    final phone = order.customerPhone ?? order.qrCustomerContact?.phone;
    final channel = _typeLabel(order.orderType);
    final time = Formatters.time(order.createdAt.toLocal());

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(9)), child: Text('#${order.orderNumber}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            Expanded(child: Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(Formatters.currency(order.grandTotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            _meta(Icons.storefront_outlined, channel),
            if (order.tableName != null) ...[const SizedBox(width: 10), _meta(Icons.table_restaurant_outlined, order.tableName!)],
            const SizedBox(width: 10),
            _meta(Icons.schedule_rounded, time),
          ]),
          if (phone != null && phone.trim().isNotEmpty) ...[const SizedBox(height: 7), _meta(Icons.phone_outlined, phone)],
          const SizedBox(height: 10),
          Row(children: [
            _badgeFor(order),
            const Spacer(),
            Text('View bill', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(width: 3),
            Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ]),
        ]),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: AppColors.textMuted), const SizedBox(width: 4), Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)))]);

  Widget _badgeFor(Order order) {
    final paid = order.paymentStatus == 'paid' || order.status == 'completed';
    final text = order.paymentMethod.isEmpty ? '—' : order.paymentMethod;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: (paid ? AppColors.success : AppColors.warning).withOpacity(.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${paid ? 'PAID' : 'PENDING'} · $text',
        style: TextStyle(
          color: paid ? AppColors.success : AppColors.warning,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _emptyState() => Container(padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), child: Column(children: [Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted), const SizedBox(height: 12), const Text('No bills found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text('Paid and payment-pending Dine In, Takeaway and Delivery bills will appear here automatically.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 11.5))]));
}
