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
  int _selected = 0;

  @override
  void initState() { super.initState(); _loadSettings(); }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService().get();
      if (!mounted) return;
      setState(() { _settings = settings; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load business settings.'; _loading = false; });
    }
  }

  Future<double> _printerWidth() async => (await SharedPreferences.getInstance()).getDouble('thermal_printer_width_mm') ?? 55;

  Future<void> _printBluetooth(KotTicket ticket) async {
    if (_settings == null) return;
    setState(() => _printing = true);
    try {
      final ok = await _kotService.printKotViaBluetooth(widget.order, _settings!, ticket, widthMm: await _printerWidth());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'KOT #${ticket.kotNumber} sent to Bluetooth printer.' : 'No Bluetooth printer is connected.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not print the KOT.')));
    } finally { if (mounted) setState(() => _printing = false); }
  }

  Future<void> _printSystem(KotTicket ticket) async {
    if (_settings == null) return;
    try { await _kotService.printKotPdf(widget.order, _settings!, ticket, widthMm: await _printerWidth()); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the KOT print dialog.'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('KOT History')), body: Center(child: Text(_error!)));
    final tickets = widget.order.kots;
    return Scaffold(
      appBar: AppBar(title: Text('KOT History • #${widget.order.orderNumber}')),
      body: tickets.isEmpty
          ? const Center(child: Text('No KOT has been sent yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [const Icon(Icons.soup_kitchen_outlined), const SizedBox(width: 10), Expanded(child: Text('${tickets.length} kitchen ticket${tickets.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800))), Text(widget.order.kitchenStatus.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))]))),
                const SizedBox(height: 12),
                ...List.generate(tickets.length, (i) {
                  final ticket = tickets[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      initiallyExpanded: i == _selected,
                      onExpansionChanged: (open) { if (open && mounted) setState(() => _selected = i); },
                      title: Text('KOT #${ticket.kotNumber}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('${ticket.status.toUpperCase()} • ${ticket.createdAt.toLocal()}'),
                      children: [
                        ...ticket.items.map((item) => ListTile(dense: true, leading: Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w900)), title: Text(item.name))),
                        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _printing ? null : () => _printBluetooth(ticket), icon: const Icon(Icons.bluetooth), label: const Text('Bluetooth'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: () => _printSystem(ticket), icon: const Icon(Icons.print), label: const Text('Print')))])),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
