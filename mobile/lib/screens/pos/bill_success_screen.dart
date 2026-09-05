import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order.dart';
import '../../models/misc_models.dart';
import '../../services/receipt_service.dart';
import '../../services/misc_services.dart';
import '../settings/printer_settings_screen.dart';

class BillSuccessScreen extends StatefulWidget {
  final Order order;
  BillSuccessScreen({super.key, required this.order});

  @override
  State<BillSuccessScreen> createState() => _BillSuccessScreenState();
}

class _BillSuccessScreenState extends State<BillSuccessScreen> {
  final _receiptService = ReceiptService();
  BusinessSettings _settings = BusinessSettings();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService().get();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Falls back to default settings — non-critical for this screen.
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not complete this action. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printOnThermalPrinter(Order order) async {
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final widthMm = prefs.getDouble('thermal_printer_width_mm') ?? 80;
      final ok = await _receiptService.printViaBluetooth(order, _settings, widthMm: widthMm);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No printer connected.'),
            action: SnackBarAction(
              label: 'Connect',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrinterSettingsScreen())),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not print the receipt. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: Icon(Icons.check_circle, color: AppColors.primary, size: 52),
              ),
              SizedBox(height: 24),
              Text('Bill Created!', style: Theme.of(context).textTheme.headlineSmall),
              SizedBox(height: 6),
              Text('Bill #${order.orderNumber}', style: Theme.of(context).textTheme.bodyLarge),
              SizedBox(height: 4),
              Text(Formatters.currency(order.grandTotal), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.primary)),
              Spacer(),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _printOnThermalPrinter(order),
                    icon: Icon(Icons.print, size: 20),
                    label: Text('Print Receipt'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runAction(() => _receiptService.shareReceipt(order, _settings)),
                    icon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text('PDF'),
                  ),
                ),
              ]),
              SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _runAction(() => _receiptService.shareTextSummary(order, _settings)),
                icon: Icon(Icons.share_outlined, size: 18),
                label: Text('Share (WhatsApp / Others)'),
              ),
              SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Text('New Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
