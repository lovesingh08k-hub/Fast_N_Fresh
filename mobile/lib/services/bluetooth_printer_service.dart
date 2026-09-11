import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A paired Bluetooth device the user can pick as their receipt printer.
class BluetoothPrinterDevice {
  final String name;
  final String macAddress;

  BluetoothPrinterDevice({
    required this.name,
    required this.macAddress,
  });
}

/// Manages the connection to a Bluetooth (Classic/SPP) thermal receipt
/// printer and sends it raw ESC/POS bytes.
///
/// This is the single place the app talks to a physical printer over
/// Bluetooth. ReceiptService only builds the ticket bytes.
///
/// Supports 58mm/80mm counter-top thermal printers.
class BluetoothPrinterService extends ChangeNotifier {
  BluetoothPrinterService._internal();

  static final BluetoothPrinterService instance =
      BluetoothPrinterService._internal();

  factory BluetoothPrinterService() => instance;

  static const _prefsMacKey = 'thermal_printer_mac';
  static const _prefsNameKey = 'thermal_printer_name';

  bool _connected = false;
  String? _connectedName;
  String? _connectedMac;

  bool get isConnected => _connected;
  String? get connectedName => _connectedName;
  String? get connectedMac => _connectedMac;

  /// Requests the Bluetooth permissions required by the current
  /// Android version.
  ///
  /// Android 12+ (API 31+):
  ///   - BLUETOOTH_SCAN
  ///   - BLUETOOTH_CONNECT
  ///
  /// Android 11 and below:
  ///   - legacy Bluetooth permission
  ///   - Location permission
  ///
  /// Location is NOT requested on Android 12+.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Android 12+ / API 31+
      //
      // Nearby devices permission is used for Bluetooth.
      // Do not request legacy Bluetooth or Location here.
      if (sdkInt >= 31) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();

        final scanGranted =
            statuses[Permission.bluetoothScan]?.isGranted == true;

        final connectGranted =
            statuses[Permission.bluetoothConnect]?.isGranted == true;

        debugPrint(
          'Bluetooth permission - scan: $scanGranted, '
          'connect: $connectGranted',
        );

        return scanGranted && connectGranted;
      }

      // Android 11 / API 30 and below.
      final statuses = await [
        Permission.bluetooth,
        Permission.location,
      ].request();

      final bluetoothGranted =
          statuses[Permission.bluetooth]?.isGranted == true;

      final locationGranted =
          statuses[Permission.location]?.isGranted == true;

      debugPrint(
        'Legacy Bluetooth permission - bluetooth: $bluetoothGranted, '
        'location: $locationGranted',
      );

      return bluetoothGranted && locationGranted;
    } catch (e, stackTrace) {
      debugPrint('Bluetooth permission error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  /// Returns whether Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('Bluetooth enabled check failed: $e');
      return false;
    }
  }

  /// Lists devices already paired with this phone/tablet.
  ///
  /// The printer must first be paired in Android Bluetooth settings.
  Future<List<BluetoothPrinterDevice>> getPairedDevices() async {
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths;

      return paired
          .map(
            (d) => BluetoothPrinterDevice(
              name: d.name,
              macAddress: d.macAdress,
            ),
          )
          .toList();
    } catch (e, stackTrace) {
      debugPrint('Failed to get paired Bluetooth devices: $e');
      debugPrintStack(stackTrace: stackTrace);

      return [];
    }
  }

  /// Connects to a paired Bluetooth thermal printer.
  Future<bool> connect(BluetoothPrinterDevice device) async {
    try {
      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAddress,
      );

      _connected = result;

      if (result) {
        _connectedName = device.name;
        _connectedMac = device.macAddress;

        await _rememberDevice(device);

        debugPrint(
          'Bluetooth printer connected: '
          '${device.name} (${device.macAddress})',
        );
      } else {
        _connectedName = null;
        _connectedMac = null;

        debugPrint(
          'Failed to connect to printer: '
          '${device.name} (${device.macAddress})',
        );
      }

      notifyListeners();

      return result;
    } catch (e, stackTrace) {
      debugPrint('Bluetooth printer connection error: $e');
      debugPrintStack(stackTrace: stackTrace);

      _connected = false;
      _connectedName = null;
      _connectedMac = null;

      notifyListeners();

      return false;
    }
  }

  /// Disconnects the currently connected printer.
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('Bluetooth disconnect error: $e');
    }

    _connected = false;
    _connectedName = null;
    _connectedMac = null;

    notifyListeners();
  }

  /// Refreshes the current Bluetooth printer connection status.
  Future<void> refreshConnectionStatus() async {
    try {
      _connected = await PrintBluetoothThermal.connectionStatus;

      if (!_connected) {
        _connectedName = null;
        _connectedMac = null;
      }
    } catch (e) {
      debugPrint('Bluetooth connection status error: $e');

      _connected = false;
      _connectedName = null;
      _connectedMac = null;
    }

    notifyListeners();
  }

  /// Tries to reconnect to the last successfully connected printer.
  Future<void> reconnectLastDevice() async {
    await refreshConnectionStatus();

    if (_connected) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final mac = prefs.getString(_prefsMacKey);
      final name = prefs.getString(_prefsNameKey);

      if (mac == null || mac.isEmpty) {
        return;
      }

      final ok = await connect(
        BluetoothPrinterDevice(
          name: name ?? 'Printer',
          macAddress: mac,
        ),
      );

      if (!ok) {
        _connected = false;
        notifyListeners();
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to reconnect last printer: $e');
      debugPrintStack(stackTrace: stackTrace);

      _connected = false;
      _connectedName = null;
      _connectedMac = null;

      notifyListeners();
    }
  }

  /// Saves the last successfully connected printer.
  Future<void> _rememberDevice(
    BluetoothPrinterDevice device,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _prefsMacKey,
      device.macAddress,
    );

    await prefs.setString(
      _prefsNameKey,
      device.name,
    );
  }

  /// Sends raw ESC/POS bytes to the connected printer.
  ///
  /// Returns false if no printer is connected or writing fails.
  Future<bool> printBytes(List<int> bytes) async {
    if (!_connected) {
      await refreshConnectionStatus();

      if (!_connected) {
        return false;
      }
    }

    try {
      final result = await PrintBluetoothThermal.writeBytes(bytes);

      if (!result) {
        debugPrint('Bluetooth printer rejected the print data.');
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint('Bluetooth print error: $e');
      debugPrintStack(stackTrace: stackTrace);

      _connected = false;
      _connectedName = null;
      _connectedMac = null;

      notifyListeners();

      return false;
    }
  }
}