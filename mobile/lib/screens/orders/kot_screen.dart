import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_exception.dart';
import '../../models/misc_models.dart';
import '../../models/order.dart';
import '../../services/kot_service.dart';
import '../../services/misc_services.dart';

class KotScreen extends StatefulWidget {
  final Order order;

  const KotScreen({super.key, required this.order});

  @override
  State<KotScreen> createState() => _KotScreenState();
}

class _KotScreenState extends State<KotScreen> {
  final _kotService = KotService();
  BusinessSettings? _settings;
  bool _loading = true;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService().get();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load business settings.';
        _loading = false;
      });
    }
  }

  Future<double> _printerWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('thermal_printer_width_mm') ?? 55;
  }

  Future<void> _printBluetooth() async {
    if (_settings == null) return;
    setState(() => _printing = true);
    try {
      final widthMm = await _printerWidth();
      final ok = await _kotService.printViaBluetooth(widget.order, _settings!, widthMm: widthMm);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'KOT sent to Bluetooth printer.' : 'No Bluetooth printer is connected.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not print KOT on the Bluetooth printer.')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _printSystem() async {
    if (_settings == null) return;
    try {
      final widthMm = await _printerWidth();
      await _kotService.printPdf(widget.order, _settings!, widthMm: widthMm);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the KOT print dialog.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final orderFrom = order.tableName?.trim().isNotEmpty == true
        ? 'Table ${order.tableName!.trim()}'
        : order.orderType == 'delivery'
            ? 'Delivery'
            : order.orderType == 'takeaway'
                ? 'Take Away'
                : 'Dine In';

    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen Order Ticket')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_settings!.cafeName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            const Text('KITCHEN ORDER TICKET', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
                            const Divider(height: 24),
                            Text('Bill No: #${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('Order from: $orderFrom'),
                            if (order.tableCustomerLabel?.trim().isNotEmpty == true)
                              Text('Customer: ${order.tableCustomerLabel!.trim()}'),
                            Text('${order.createdAt.toLocal()}'),
                            const Divider(height: 24),
                            const Row(
                              children: [
                                SizedBox(width: 52, child: Text('QTY', style: TextStyle(fontWeight: FontWeight.w900))),
                                Expanded(child: Text('ITEM', style: TextStyle(fontWeight: FontWeight.w900))),
                              ],
                            ),
                            const Divider(height: 12),
                            ...order.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    SizedBox(width: 52, child: Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w900))),
                                    Expanded(child: Text(item.name)),
                                  ],
                                ),
                              ),
                            ),
                            if (order.notes?.trim().isNotEmpty == true) ...[
                              const Divider(height: 24),
                              const Text('NOTE', style: TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(order.notes!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _printing ? null : _printBluetooth,
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Print KOT — Bluetooth'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _printSystem,
                      icon: const Icon(Icons.print),
                      label: const Text('Print KOT — System'),
                    ),
                  ],
                ),
    );
  }
}
