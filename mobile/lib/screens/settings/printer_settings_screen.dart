import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../services/bluetooth_printer_service.dart';

/// Lets staff pick, connect to, and test the café's Bluetooth thermal
/// receipt printer (55mm/80mm roll) — the printer used at the billing
/// counter. This does not touch the A4/PDF "Share as PDF" option, which
/// remains available separately for emailing/WhatsApp-ing a bill copy.
class PrinterSettingsScreen extends StatefulWidget {
  PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  static const _prefsWidthKey = 'thermal_printer_width_mm';

  final _service = BluetoothPrinterService();
  List<BluetoothPrinterDevice> _devices = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  double _widthMm = 80;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _init();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _widthMm = prefs.getDouble(_prefsWidthKey) ?? 55;
    // Permissions must be granted BEFORE we ask the OS for Bluetooth
    // adapter/connection state. On Android 12+ the service requests only
    // Nearby Devices (SCAN/CONNECT), avoiding false denials from legacy
    // BLUETOOTH/location permissions that are not applicable on API 31+.
    final granted = await _service.requestPermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Nearby devices / Bluetooth permission is required. Tap Refresh after allowing it in App settings.';
        _devices = [];
      });
      return;
    }
    await _service.reconnectLastDevice();
    await _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final granted = await _service.requestPermissions();
      if (!granted) {
        setState(() {
          _error = 'Nearby devices / Bluetooth permission is required. Open App settings and allow Nearby devices / Bluetooth, then tap Refresh.';
          _devices = [];
        });
        return;
      }
      final enabled = await _service.isBluetoothEnabled();
      if (!enabled) {
        setState(() {
          _error = 'Bluetooth is turned off. Turn it on, then pull to refresh.';
          _devices = [];
        });
        return;
      }
      final devices = await _service.getPairedDevices();
      setState(() => _devices = devices);
      // A previously-connected printer may have been powered off/back on
      // since this screen last checked — make sure the header reflects the
      // real, current connection state rather than stale in-memory state.
      await _service.refreshConnectionStatus();
    } catch (_) {
      setState(() => _error = 'Could not read paired Bluetooth devices.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(BluetoothPrinterDevice device) async {
    setState(() => _busy = true);
    try {
      final ok = await _service.connect(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Connected to ${device.name}.' : 'Could not connect to ${device.name}.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _service.disconnect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setWidth(double mm) async {
    setState(() => _widthMm = mm);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsWidthKey, mm);
  }

  Future<void> _printTest() async {
    if (!_service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a printer first.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final isNarrow = _widthMm <= 60;
      final chars = isNarrow ? 30 : 48;
      final dash = List.filled(chars, '-').join();
      final lines = <int>[
        ...'Fast N Fresh Cafe\n'.codeUnits,
        ...'TEST PRINT\n'.codeUnits,
        ...'$dash\n'.codeUnits,
        ...'Paper: ${isNarrow ? '55mm' : '80mm'}\n'.codeUnits,
        ...'Printer: ${_service.connectedName ?? '-'}\n'.codeUnits,
        ...'$dash\n\n\n'.codeUnits,
      ];
      final ok = await _service.printBytes(lines);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Test receipt sent.' : 'Test print failed — check the connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Receipt Printer')),
      body: RefreshIndicator(
        onRefresh: _refreshDevices,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _service.isConnected ? AppColors.primaryLight : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _service.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: _service.isConnected ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _service.isConnected ? 'Connected: ${_service.connectedName ?? ''}' : 'No printer connected',
                      style: TextStyle(fontWeight: FontWeight.w600, color: _service.isConnected ? AppColors.primary : AppColors.textSecondary),
                    ),
                  ),
                  if (_service.isConnected)
                    TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Paper Width', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('55 mm'),
                    selected: _widthMm <= 60,
                    onSelected: (_) => _setWidth(55),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('80 mm'),
                    selected: _widthMm > 60,
                    onSelected: (_) => _setWidth(80),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Paired Devices', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _loading ? null : _refreshDevices,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: TextStyle(color: AppColors.danger)),
              ),
            if (!_loading && _error == null && _devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.print_disabled_outlined, size: 40, color: AppColors.textMuted),
                    const SizedBox(height: 10),
                    Text(
                      'No paired printer found. Pair your Bluetooth thermal printer in your device\'s Bluetooth settings first, then refresh here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ..._devices.map(
              (d) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: ListTile(
                  leading: Icon(Icons.print_outlined, color: _service.connectedMac == d.macAddress ? AppColors.primary : AppColors.textMuted),
                  title: Text(d.name.isNotEmpty ? d.name : d.macAddress),
                  subtitle: Text(d.macAddress),
                  trailing: _service.connectedMac == d.macAddress
                      ? Icon(Icons.check_circle, color: AppColors.primary)
                      : TextButton(onPressed: _busy ? null : () => _connect(d), child: const Text('Connect')),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _busy || !_service.isConnected ? null : _printTest,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Print Test Receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
