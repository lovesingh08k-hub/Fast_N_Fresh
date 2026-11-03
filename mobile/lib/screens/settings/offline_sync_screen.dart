import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/offline/offline_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// What is saved on this device and not yet on the server. Sending happens by
/// itself; this page shows it, and is where a refused bill can be seen.
class OfflineSyncScreen extends StatelessWidget {
  const OfflineSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<OfflineEngine>();
    final pending = engine.pendingOrders;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(context, engine),
          const SizedBox(height: 16),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.cloud_done_rounded, size: 52, color: AppColors.success),
                  const SizedBox(height: 10),
                  Text('Everything is on the server', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ],
              ),
            )
          else ...[
            Text('Waiting to send (${pending.length})', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            for (final order in pending) _orderRow(order),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, OfflineEngine engine) {
    final offline = engine.isOffline;
    final color = offline ? AppColors.warning : AppColors.success;
    final title = engine.isSyncing
        ? 'Sending to server...'
        : offline
            ? 'Offline: billing still works'
            : 'Online';
    final detail = offline
        ? 'Bills and orders are saved on this phone and go to the server by themselves when the internet is back.'
        : engine.hasPending
            ? 'Sending saved work to the server.'
            : engine.lastSyncAt == null
                ? 'Nothing is waiting.'
                : 'Last sent at ${Formatters.time(engine.lastSyncAt!)}.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
            ],
          ),
          const SizedBox(height: 8),
          Text(detail, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: engine.isSyncing ? null : () => engine.retryFailed(),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Sync now'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> order) {
    final sync = (order['_sync'] as Map?) ?? const {};
    final failed = sync['state'] == 'failed';
    final paid = order['status'] == 'completed';
    final cancelled = order['status'] == 'voided';
    final ref = order['offlineRef'] ?? '#${order['orderNumber']}';
    final table = order['table'] is Map ? (order['table'] as Map)['name'] : order['tableCustomerLabel'];
    final kind = cancelled ? 'Cancelled order' : (paid ? 'Paid bill' : 'Running order');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed ? AppColors.danger : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('$ref', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              Text(Formatters.currency(((order['grandTotal'] as num?) ?? 0).toDouble()), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$kind${table == null ? '' : ' · $table'}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          if (failed) ...[
            const SizedBox(height: 6),
            Text('${sync['error'] ?? 'The server refused this.'}', style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
