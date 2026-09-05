import 'package:flutter/foundation.dart';

/// Coordinates explicit refreshes across the shell without restarting the app.
class TabRefreshBus extends ChangeNotifier {
  int dashboardTick = 0;
  int appRefreshTick = 0;
  bool _refreshing = false;

  bool get isRefreshing => _refreshing;

  void bumpDashboard() {
    dashboardTick++;
    notifyListeners();
  }

  Future<void> refreshWholeApp({Future<void> Function()? beforeRebuild}) async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      if (beforeRebuild != null) await beforeRebuild();
      appRefreshTick++;
      dashboardTick++;
      notifyListeners();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }
}
