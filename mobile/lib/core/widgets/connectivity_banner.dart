import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../providers/auth_provider.dart';
import '../../screens/settings/offline_sync_screen.dart';
import '../theme/app_colors.dart';
import '../network/network_status.dart';
import '../offline/offline_engine.dart';
import '../../providers/connectivity_provider.dart';

/// Wraps the app and shows a strip above every page whenever the server cannot
/// be reached normally, so the user always knows what is going on:
///
/// - Offline: billing carries on from this device, and the strip says how much
///   is waiting. Tapping it opens the Offline Sync page.
/// - Device online but requests to the backend are being auto-retried
///   (e.g. a sleeping Render instance waking up) → "Waking up the server…",
///   sourced from [NetworkStatus], which DioClient's retry interceptor updates.
///
/// It sits above the page rather than on top of it: offline can last for hours,
/// and page headers and back buttons must stay usable all that time.
class ConnectivityBanner extends StatelessWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  String _offlineText(OfflineEngine offline, bool signedIn) {
    if (!signedIn) return 'No internet connection';
    final bills = offline.unsyncedBills;
    return bills > 0
        ? 'Offline: billing works. $bills bill${bills == 1 ? '' : 's'} will sync later'
        : 'Offline: billing works. Will sync when back online';
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final networkStatus = context.watch<NetworkStatus>();
    final offline = context.watch<OfflineEngine>();
    final signedIn = context.watch<AuthProvider>().status == AuthStatus.authenticated;

    final showOffline = !isOnline || offline.isOffline;
    final showReconnecting = !showOffline && networkStatus.isRetrying;
    final show = showOffline || showReconnecting;

    return Column(
      children: [
        if (show)
          Material(
            color: showOffline ? AppColors.warning : AppColors.info,
            child: InkWell(
              onTap: showOffline && signedIn
                  ? () => PwpPosApp.navigatorKey.currentState?.push(
                        MaterialPageRoute(builder: (_) => const OfflineSyncScreen()),
                      )
                  : null,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        showOffline ? Icons.wifi_off_rounded : Icons.cloud_sync_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          showOffline ? _offlineText(offline, signedIn) : 'Waking up the server. Please wait…',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: show,
            child: child,
          ),
        ),
      ],
    );
  }
}
