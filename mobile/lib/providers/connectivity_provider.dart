import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Tracks device network connectivity so screens can show a clean
/// "No internet connection" state instead of silently failing.
class ConnectivityProvider extends ChangeNotifier {
  bool isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    final results = await Connectivity().checkConnectivity();
    isOnline = !results.contains(ConnectivityResult.none);
    notifyListeners();

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      if (online != isOnline) {
        isOnline = online;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
