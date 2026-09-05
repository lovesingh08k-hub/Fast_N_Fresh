import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A paired Bluetooth device the user can pick as their receipt printer.
class BluetoothPrinterDevice {
  final String name;
  final String macAddress;
  BluetoothPrinterDevice({required this.name, required this.macAddress});
}

/// Manages the connection to a Bluetooth (Classic/SPP) thermal receipt
/// printer, and sends it raw ESC/POS bytes.
///
/// This is the single place the app talks to a physical printer over
/// Bluetooth — [ReceiptService] only builds the ticket bytes; this service
/// is what actually finds, connects to, and writes to the printer, and
/// remembers the last-used printer between app launches (58mm/80mm
/// counter-top thermal printers, not the A4/PDF system print dialog).
class BluetoothPrinterService extends ChangeNotifier {
  BluetoothPrinterService._internal();
  static final BluetoothPrinterService instance = BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => instance;

  static const _prefsMacKey = 'thermal_printer_mac';
  static const _prefsNameKey = 'thermal_printer_name';

  bool _connected = false;
  String? _connectedName;
  String? _connectedMac;

  bool get isConnected => _connected;
  String? get connectedName => _connectedName;
  String? get connectedMac => _connectedMac;

  /// Requests the Bluetooth (and, on older Android, location) permissions
  /// needed to see and connect to paired devices. Returns true if granted.
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    // Not every one of these permissions exists on every Android version —
    // the plugin reports the ones that don't apply as already-granted.
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Lists devices already paired with this phone/tablet in Android's
  /// Bluetooth settings. Thermal receipt printers must be paired there
  /// first (standard PIN, usually 0000 or 1234) — this app does not do
  /// discovery/pairing itself, only connects to an already-paired device.
  Future<List<BluetoothPrinterDevice>> getPairedDevices() async {
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return paired
        .map((d) => BluetoothPrinterDevice(name: d.name, macAddress: d.macAdress))
        .toList();
  }

  Future<bool> connect(BluetoothPrinterDevice device) async {
    final result = await PrintBluetoothThermal.connect(macPrinterAddress: device.macAddress);
    _connected = result;
    if (result) {
      _connectedName = device.name;
      _connectedMac = device.macAddress;
      await _rememberDevice(device);
    }
    notifyListeners();
    return result;
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Already disconnected — nothing to do.
    }
    _connected = false;
    _connectedName = null;
    _connectedMac = null;
    notifyListeners();
  }

  Future<void> refreshConnectionStatus() async {
    try {
      _connected = await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      _connected = false;
    }
    notifyListeners();
  }

  /// Tries to reconnect to whichever printer was last connected
  /// successfully, if any. Called on app/screen startup so staff don't
  /// have to reselect the printer every time.
  Future<void> reconnectLastDevice() async {
    await refreshConnectionStatus();
    if (_connected) return;

    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_prefsMacKey);
    final name = prefs.getString(_prefsNameKey);
    if (mac == null) return;

    final ok = await connect(BluetoothPrinterDevice(name: name ?? 'Printer', macAddress: mac));
    if (!ok) {
      _connected = false;
      notifyListeners();
    }
  }

  Future<void> _rememberDevice(BluetoothPrinterDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsMacKey, device.macAddress);
    await prefs.setString(_prefsNameKey, device.name);
  }

  /// Sends raw ESC/POS bytes (as built by ReceiptService) to the connected
  /// printer. Returns false if nothing is connected or the write failed.
  Future<bool> printBytes(List<int> bytes) async {
    if (!_connected) {
      await refreshConnectionStatus();
      if (!_connected) return false;
    }
    try {
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      _connected = false;
      notifyListeners();
      return false;
    }
  }
}
