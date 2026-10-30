import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_widgets.dart';
import '../../services/misc_services.dart';

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _rate(Object? r) {
  final v = _n(r);
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

Widget _section(String title, List<Widget> children) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

Widget _row(String label, String value, {bool bold = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color)),
      ],
    ),
  );
}

// ============================================================
// GST REPORT
// ============================================================

/// GST summary for filing: taxable value and CGST/SGST/IGST per rate for
/// a month (or a custom range), plus the invoice number range.
class GstReportTab extends StatefulWidget {
  final ReportService service;
  const GstReportTab({super.key, required this.service});

  @override
  State<GstReportTab> createState() => _GstReportTabState();
}

class _GstReportTabState extends State<GstReportTab> {
  late DateTimeRange _range;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final end = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59);
      final data = await widget.service.taxReport(from: _range.start, to: end);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the GST report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setMonth(int monthsBack) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - monthsBack);
    final end = monthsBack == 0 ? now : DateTime(start.year, start.month + 1, 0);
    setState(() => _range = DateTimeRange(start: start, end: end));
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _share() async {
    final d = _data;
    if (d == null) return;
    final b = StringBuffer()
      ..writeln('GST report ${_ymd(_range.start)} to ${_ymd(_range.end)}')
      ..writeln('Bills: ${d['bills']}  Invoices: ${d['firstInvoice'] ?? '-'} to ${d['lastInvoice'] ?? '-'}')
      ..writeln('Rate,Taxable,CGST,SGST,IGST,Total GST');
    for (final r in (d['rates'] as List? ?? const [])) {
      b.writeln('${_rate(r['rate'])}%,${_n(r['taxable']).toStringAsFixed(2)},${_n(r['cgst']).toStringAsFixed(2)},'
          '${_n(r['sgst']).toStringAsFixed(2)},${_n(r['igst']).toStringAsFixed(2)},${_n(r['tax']).toStringAsFixed(2)}');
    }
    b.writeln('Net sales,${_n(d['netSales']).toStringAsFixed(2)}');
    await Share.share(b.toString());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(label: const Text('This month'), onPressed: () => _setMonth(0)),
              ActionChip(label: const Text('Last month'), onPressed: () => _setMonth(1)),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text('${Formatters.shortDate(_range.start)} – ${Formatters.shortDate(_range.end)}'),
                onPressed: _pickRange,
              ),
              if (_data != null)
                ActionChip(avatar: const Icon(Icons.share_outlined, size: 18), label: const Text('Share'), onPressed: _share),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            ErrorState(message: _error!, onRetry: _load)
          else
            ..._body(_data!),
        ],
      ),
    );
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final rates = (d['rates'] as List? ?? const []).cast<Map>();
    return [
      _section('Summary', [
        _row('Bills', '${d['bills'] ?? 0}'),
        _row('Invoices', '${d['firstInvoice'] ?? '-'}  →  ${d['lastInvoice'] ?? '-'}'),
        _row('Items total', Formatters.currency(_n(d['subtotal']))),
        _row('Discount', '- ${Formatters.currency(_n(d['discount']))}'),
        if (_n(d['serviceCharge']) > 0) _row('Service charge', Formatters.currency(_n(d['serviceCharge']))),
        if (_n(d['packagingCharge']) > 0) _row('Packaging', Formatters.currency(_n(d['packagingCharge']))),
        if (_n(d['deliveryCharge']) > 0) _row('Delivery charge', Formatters.currency(_n(d['deliveryCharge']))),
        _row('Total GST', Formatters.currency(_n(d['tax'])), color: AppColors.primary),
        if (_n(d['roundOff']) != 0) _row('Round off', Formatters.currency(_n(d['roundOff']))),
        const Divider(),
        _row('Net sales', Formatters.currency(_n(d['netSales'])), bold: true),
      ]),
      _section('GST by rate', [
        if (rates.isEmpty)
          Text('No GST charged in this period. Turn on GST in Settings → Billing.', style: TextStyle(color: AppColors.textMuted))
        else
          for (final r in rates) ...[
            _row('${_rate(r['rate'])}% on ${Formatters.currency(_n(r['taxable']))}', Formatters.currency(_n(r['tax'])), bold: true),
            if (_n(r['igst']) > 0)
              _row('   IGST', Formatters.currency(_n(r['igst'])))
            else ...[
              _row('   CGST ${_rate(_n(r['rate']) / 2)}%', Formatters.currency(_n(r['cgst']))),
              _row('   SGST ${_rate(_n(r['rate']) / 2)}%', Formatters.currency(_n(r['sgst']))),
            ],
            const SizedBox(height: 6),
          ],
      ]),
    ];
  }
}

// ============================================================
// DAY-END (Z) REPORT
// ============================================================

/// Day-end (Z) report: bills, sales, GST, payments by mode, cancelled and
/// complimentary bills, expenses and the top items of one day.
class DayEndReportTab extends StatefulWidget {
  final ReportService service;
  const DayEndReportTab({super.key, required this.service});

  @override
  State<DayEndReportTab> createState() => _DayEndReportTabState();
}

class _DayEndReportTabState extends State<DayEndReportTab> {
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.dayEndReport(_ymd(_date));
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the day-end report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked == null) return;
    setState(() => _date = picked);
    _load();
  }

  Future<void> _share() async {
    final d = _data;
    if (d == null) return;
    final p = (d['payments'] as Map?) ?? const {};
    final b = StringBuffer()
      ..writeln('DAY-END REPORT ${d['date']}')
      ..writeln('Bills: ${d['bills']}  Cancelled: ${d['cancelled']}  Open: ${d['openBills']}')
      ..writeln('Invoices: ${d['firstInvoice'] ?? '-'} to ${d['lastInvoice'] ?? '-'}')
      ..writeln('Items total: ${Formatters.currency(_n(d['subtotal']))}')
      ..writeln('Discount: ${Formatters.currency(_n(d['discount']))}')
      ..writeln('GST: ${Formatters.currency(_n(d['tax']))}')
      ..writeln('NET SALES: ${Formatters.currency(_n(d['netSales']))}')
      ..writeln('Cash ${Formatters.currency(_n(p['cash']))} | UPI ${Formatters.currency(_n(p['upi']))} | '
          'Card ${Formatters.currency(_n(p['card']))} | Online ${Formatters.currency(_n(p['online']))} | '
          'Credit ${Formatters.currency(_n(p['credit']))}')
      ..writeln('Expenses: ${Formatters.currency(_n(d['expenses']))}  Refunds: ${Formatters.currency(_n(d['refunds']))}');
    await Share.share(b.toString());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(Formatters.date(_date)),
              ),
              const Spacer(),
              if (_data != null)
                IconButton(tooltip: 'Share', onPressed: _share, icon: const Icon(Icons.share_outlined)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            ErrorState(message: _error!, onRetry: _load)
          else
            ..._body(_data!),
        ],
      ),
    );
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final payments = (d['payments'] as Map?) ?? const {};
    final byType = (d['byType'] as Map?) ?? const {};
    final complimentary = (d['complimentary'] as Map?) ?? const {};
    final taxes = (d['taxes'] as List? ?? const []).cast<Map>();
    final items = (d['topItems'] as List? ?? const []).cast<Map>();
    return [
      _section('Sales', [
        _row('Bills', '${d['bills'] ?? 0}'),
        _row('Cancelled bills', '${d['cancelled'] ?? 0}'),
        if ((d['openBills'] ?? 0) > 0) _row('Still open (unbilled)', '${d['openBills']}', color: AppColors.warning),
        _row('Invoices', '${d['firstInvoice'] ?? '-'}  →  ${d['lastInvoice'] ?? '-'}'),
        const Divider(),
        _row('Items total', Formatters.currency(_n(d['subtotal']))),
        _row('Discount', '- ${Formatters.currency(_n(d['discount']))}'),
        if (_n(d['serviceCharge']) > 0) _row('Service charge', Formatters.currency(_n(d['serviceCharge']))),
        if (_n(d['packagingCharge']) > 0) _row('Packaging', Formatters.currency(_n(d['packagingCharge']))),
        if (_n(d['deliveryCharge']) > 0) _row('Delivery charge', Formatters.currency(_n(d['deliveryCharge']))),
        _row('GST', Formatters.currency(_n(d['tax']))),
        if (_n(d['roundOff']) != 0) _row('Round off', Formatters.currency(_n(d['roundOff']))),
        const Divider(),
        _row('Net sales', Formatters.currency(_n(d['netSales'])), bold: true, color: AppColors.primary),
      ]),
      _section('Payments', [
        _row('Cash', Formatters.currency(_n(payments['cash']))),
        _row('UPI', Formatters.currency(_n(payments['upi']))),
        _row('Card', Formatters.currency(_n(payments['card']))),
        _row('Online (Swiggy/Zomato)', Formatters.currency(_n(payments['online']))),
        _row('Credit / UDHAR', Formatters.currency(_n(payments['credit']))),
        const Divider(),
        _row('Refunds', '- ${Formatters.currency(_n(d['refunds']))}'),
        _row('Expenses (cash ${Formatters.currency(_n(d['cashExpenses']))})', '- ${Formatters.currency(_n(d['expenses']))}'),
      ]),
      _section('By order type', [
        _row('Dine-in', Formatters.currency(_n(byType['dine_in']))),
        _row('Takeaway', Formatters.currency(_n(byType['takeaway']))),
        _row('Delivery', Formatters.currency(_n(byType['delivery']))),
        if ((complimentary['bills'] ?? 0) > 0)
          _row('Complimentary (${complimentary['bills']} bills)', Formatters.currency(_n(complimentary['value'])), color: AppColors.warning),
      ]),
      if (taxes.isNotEmpty)
        _section('GST by rate', [
          for (final t in taxes)
            _row('${_rate(t['rate'])}% on ${Formatters.currency(_n(t['taxable']))}', Formatters.currency(_n(t['tax']))),
        ]),
      if (items.isNotEmpty)
        _section('Top items', [
          for (final i in items) _row('${i['name']}  ×${i['quantity']}', Formatters.currency(_n(i['amount']))),
        ]),
    ];
  }
}
