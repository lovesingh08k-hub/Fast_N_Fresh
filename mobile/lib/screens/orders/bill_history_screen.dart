import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import 'open_bill.dart';

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
      case 'Today':
        return today;
      case 'Yesterday':
        return today.subtract(const Duration(days: 1));
      case 'This Week':
        return today.subtract(Duration(days: today.weekday - 1));
      case 'This Month':
        return DateTime(today.year, today.month, 1);
      case 'All':
        return null;
      default:
        return today;
    }
  }

  DateTime? get _to {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime end(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    switch (_period) {
      case 'Today':
        return end(today);
      case 'Yesterday':
        return end(today.subtract(const Duration(days: 1)));
      case 'This Week':
        return end(today.add(Duration(days: 7 - today.weekday)));
      case 'This Month':
        final next = today.month == 12
            ? DateTime(today.year + 1, 1, 1)
            : DateTime(today.year, today.month + 1, 1);
        return end(next.subtract(const Duration(days: 1)));
      case 'All':
        return null;
      default:
        return end(today);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_bills.isEmpty) {
      try {
        final saved = await _service.listCached(from: _from, to: _to, paymentMethod: _payment, orderType: _type, search: _search.text, limit: 100);
        if (saved != null && mounted && _bills.isEmpty) {
          setState(() => _bills = saved.where((o) => o.status != 'voided').toList());
        }
      } catch (_) {
        // The fresh load fills the screen anyway.
      }
    }
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
      setState(
          () => _bills = bills.where((o) => o.status != 'voided').toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load bills.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'dine_in':
        return 'Dine In';
      case 'takeaway':
        return 'Takeaway';
      case 'delivery':
        return 'Delivery';
      default:
        return 'All types';
    }
  }

  String _paymentLabel(String? method) => method ?? 'All payments';

  @override
  Widget build(BuildContext context) {
    final total = _bills.fold<double>(0, (sum, o) => sum + o.grandTotal);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              FreshHeader(
                title: 'Bills',
                showBack: Navigator.of(context).canPop(),
                actions: [
                  FreshHeaderAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _summary(
                total,
                paid: _bills
                    .where((o) =>
                        o.paymentStatus == 'paid' || o.status == 'completed')
                    .fold<double>(0, (sum, o) => sum + o.grandTotal),
                pending: _bills
                    .where((o) =>
                        o.paymentStatus != 'paid' && o.status != 'completed')
                    .fold<double>(0, (sum, o) => sum + o.grandTotal),
              ),
              const SizedBox(height: 12),
              _searchBox(),
              const SizedBox(height: 10),
              _filters(),
              const SizedBox(height: 12),
              if (_error != null)
                InlineRetryBanner(message: _error!, onRetry: _load),
              if (_loading && _bills.isEmpty)
                const SectionLoadingBox(height: 220)
              else if (!_loading && _bills.isEmpty)
                _emptyState()
              else
                ..._bills.map(_billCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(double total,
      {required double paid, required double pending}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: FreshUi.card(tintStrength: .08),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sales Register',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(Formatters.currency(total),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text:
                            '${_bills.length} bill${_bills.length == 1 ? '' : 's'} · $_period'),
                    if (pending > 0) ...[
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                          text: 'Paid ${Formatters.currency(paid)}',
                          style: const TextStyle(color: FreshUi.mint)),
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                          text: 'Pending ${Formatters.currency(pending)}',
                          style: const TextStyle(color: FreshUi.amber)),
                    ],
                  ]),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FreshUi.mint.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: FreshUi.mint, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.border),
    );
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _load(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search bill no, customer or phone',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: FreshUi.mint, width: 1.3)),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _search.clear();
                  _load();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded, size: 18)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _filterChip(Icons.calendar_today_outlined, _period, _period != 'Today',
            () => _periodSheet()),
        const SizedBox(width: 8),
        _filterChip(Icons.restaurant_menu_rounded, _typeLabel(_type),
            _type != null, () => _typeSheet()),
        const SizedBox(width: 8),
        _filterChip(Icons.payments_outlined, _paymentLabel(_payment),
            _payment != null, () => _paymentSheet()),
      ]),
    );
  }

  // Each filter has its own icon and a dropdown arrow, and is tinted when it
  // differs from the default so active filters are visible at a glance.
  Widget _filterChip(
      IconData icon, String label, bool active, VoidCallback onTap) {
    final color = active ? FreshUi.mint : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? FreshUi.mint.withValues(alpha: .12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active
                    ? FreshUi.mint.withValues(alpha: .6)
                    : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: color),
          ]),
        ),
      ),
    );
  }

  Future<void> _periodSheet() async {
    final value = await _pick(
        ['Today', 'Yesterday', 'This Week', 'This Month', 'All'],
        _period,
        'Bill period');
    if (value != null && mounted) {
      setState(() => _period = value);
      _load();
    }
  }

  Future<void> _typeSheet() async {
    final value = await _pick(['All', 'Dine In', 'Takeaway', 'Delivery'],
        _type == null ? 'All' : _typeLabel(_type), 'Order type');
    if (value != null && mounted) {
      setState(() => _type = value == 'All'
          ? null
          : {
              'Dine In': 'dine_in',
              'Takeaway': 'takeaway',
              'Delivery': 'delivery'
            }[value]);
      _load();
    }
  }

  Future<void> _paymentSheet() async {
    final value = await _pick(['All', 'CASH', 'UPI', 'CREDIT', 'MIXED'],
        _payment ?? 'All', 'Payment method');
    if (value != null && mounted) {
      setState(() => _payment = value == 'All' ? null : value);
      _load();
    }
  }

  Future<String?> _pick(List<String> options, String selected, String title) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)))),
        ...options.map((option) => ListTile(
            title: Text(option),
            trailing: option == selected
                ? Icon(Icons.check_rounded, color: AppColors.primary)
                : null,
            onTap: () => Navigator.pop(context, option))),
        const SizedBox(height: 8),
      ])),
    );
  }

  Widget _billCard(Order order) {
    final customer = order.customerName ??
        order.qrCustomerContact?.name ??
        'Walk-in customer';
    final phone = order.customerPhone ?? order.qrCustomerContact?.phone;
    final time = Formatters.time(order.createdAt.toLocal());
    final details = [
      _typeLabel(order.orderType),
      if (order.tableName != null) order.tableName!,
      time,
      if (phone != null && phone.trim().isNotEmpty) phone.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await openBill(context, order);
            if (mounted) _load();
          },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FreshUi.mint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('#${order.orderNumber}',
                      style: const TextStyle(
                          color: FreshUi.mint,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formatters.currency(order.grandTotal),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  _badgeFor(order),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badgeFor(Order order) {
    final paid = order.paymentStatus == 'paid' || order.status == 'completed';
    final text = order.paymentMethod.isEmpty ? '—' : order.paymentMethod;
    final color = paid ? FreshUi.mint : FreshUi.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        paid ? text : 'PENDING · $text',
        style: TextStyle(
          color: color,
          fontSize: 10,
          letterSpacing: .3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
      padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        const Text('No bills found',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(
            'Paid and payment-pending Dine In, Takeaway and Delivery bills will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5))
      ]));
}
