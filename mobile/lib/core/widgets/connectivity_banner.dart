import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../network/network_status.dart';
import '../../providers/connectivity_provider.dart';

/// Wraps the app and shows a persistent banner whenever something is
/// stopping requests from completing normally, so POS operations never
/// silently fail — the user always sees why an action isn't working:
///
/// - Device offline (no internet at all) → red "No internet connection".
/// - Device online but requests to the backend are being auto-retried
///   (e.g. a sleeping Render instance waking up) → blue "Waking up the
///   server…", sourced from [NetworkStatus], which DioClient's retry
///   interceptor updates directly.
///
/// Offline always takes priority when both are true, since there's no
/// point telling the user the server is waking up when their device has
/// no connection to reach it at all.
class ConnectivityBanner extends StatelessWidget {
  final Widget child;
  ConnectivityBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final networkStatus = context.watch<NetworkStatus>();

    final showOffline = !isOnline;
    final showReconnecting = isOnline && networkStatus.isRetrying;

    return Stack(
      children: [
        child,
        if (showOffline || showReconnecting)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.all(10),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: showOffline ? AppColors.danger : AppColors.info,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    Icon(
                      showOffline ? Icons.wifi_off_rounded : Icons.cloud_sync_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        showOffline ? 'No internet connection' : 'Waking up the server. Please wait…',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
