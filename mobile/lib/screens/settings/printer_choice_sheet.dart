import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../services/bluetooth_printer_service.dart';
import 'printer_settings_screen.dart';

/// Shopto-style printer choice used before printing KOT/receipts.
/// The choice is persisted so the next print uses the same mode.
class PrinterChoiceSheet extends StatelessWidget {
  const PrinterChoiceSheet({super.key});

  static const printModeKey = 'print_mode';
  static const bluetoothMode = 'bluetooth';

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PrinterChoiceSheet(),
    );
  }

  Future<void> _selectPrinter(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PrinterSettingsScreen()),
    );
    if (!context.mounted) return;

    final service = BluetoothPrinterService();
    if (service.isConnected) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(printModeKey, bluetoothMode);
      if (context.mounted) Navigator.pop(context, bluetoothMode);
    } else if (result == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(printModeKey, bluetoothMode);
      if (context.mounted) Navigator.pop(context, bluetoothMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Connect to Printer',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.black54),
                ),
              ],
            ),
            const Divider(height: 24),
            const SizedBox(height: 18),
            Icon(Icons.print_outlined, size: 54, color: AppColors.primary),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: () => _selectPrinter(context),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Select Printer'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: const Text('Cancel', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}
