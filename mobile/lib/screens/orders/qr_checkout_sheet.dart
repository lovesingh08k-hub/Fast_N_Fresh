import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';

class QrCheckoutSheet extends StatefulWidget {
  final Order order;
  const QrCheckoutSheet({super.key, required this.order});

  @override
  State<QrCheckoutSheet> createState() => _QrCheckoutSheetState();
}

class _QrCheckoutSheetState extends State<QrCheckoutSheet> {
  String _method = 'CASH';
  late final TextEditingController _cashController;
  late final TextEditingController _upiController;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.order.paymentMethod == 'UPI' ? 'UPI' : 'CASH';
    _cashController = TextEditingController();
    _upiController = TextEditingController(text: widget.order.upiReference ?? '');
  }

  @override
  void dispose() {
    _cashController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  double get _cashReceived => double.tryParse(_cashController.text.trim()) ?? 0;

  Future<void> _checkout() async {
    if (_busy) return;
    final total = widget.order.grandTotal;
    if (_method == 'CASH' && _cashReceived < total) {
      setState(() => _error = 'Amount received must be at least ${Formatters.currency(total)}.');
      return;
    }
    if (_method == 'UPI' && _upiController.text.trim().isEmpty) {
      setState(() => _error = 'Enter and verify the UPI reference / UTR before checkout.');
      return;
    }

    setState(() { _busy = true; _error = null; });
    try {
      final updated = await OrderService().checkoutOrder(
        widget.order.id,
        paymentMethod: _method,
        amountReceived: _method == 'CASH' ? _cashReceived : null,
        upiReference: _method == 'UPI' ? _upiController.text.trim() : null,
        discount: widget.order.discount,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not complete checkout. Please try again.'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.order.grandTotal;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Complete Bill', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              Text(Formatters.currency(total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ]),
            const SizedBox(height: 6),
            Text('Verify payment first. Checkout will mark the order paid and close it.', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'CASH', label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: 'UPI', label: Text('UPI'), icon: Icon(Icons.account_balance_wallet_outlined)),
              ],
              selected: {_method},
              onSelectionChanged: _busy ? null : (v) => setState(() { _method = v.first; _error = null; }),
            ),
            const SizedBox(height: 14),
            if (_method == 'CASH') TextField(
              controller: _cashController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(labelText: 'Amount received', prefixText: '₹ ', prefixIcon: const Icon(Icons.payments_outlined)),
            ),
            if (_method == 'UPI') TextField(
              controller: _upiController,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: 'UPI Reference / UTR', prefixIcon: Icon(Icons.tag)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _busy ? null : _checkout,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
              label: Text(_busy ? 'Completing...' : 'Verify & Complete Bill'),
            )),
          ]),
        ),
      ),
    );
  }
}
