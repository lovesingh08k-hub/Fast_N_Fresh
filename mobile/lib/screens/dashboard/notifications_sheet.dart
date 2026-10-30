import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/dashboard_models.dart';
import '../inventory/inventory_screen.dart';

/// What happened recently, built from the dashboard data: new orders (QR
/// orders highlighted), completed payments and low stock.
class HomeNotice {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool unread;
  final VoidCallback? onTap;

  const HomeNotice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.unread = false,
    this.onTap,
  });

  static List<HomeNotice> fromDashboard(BuildContext context, DashboardData data) {
    final notices = <HomeNotice>[];
    if (data.lowStockCount > 0) {
      notices.add(HomeNotice(
        icon: Icons.inventory_2_rounded,
        color: AppColors.danger,
        title: '${data.lowStockCount} item${data.lowStockCount == 1 ? ' is' : 's are'} low on stock',
        subtitle: 'Tap to restock',
        unread: true,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryScreen())),
      ));
    }
    for (final o in data.recentOrders.take(12)) {
      final ago = Formatters.relative(o.createdAt);
      if (o.status == 'completed') {
        notices.add(HomeNotice(
          icon: Icons.payments_rounded,
          color: AppColors.success,
          title: 'Payment received for bill #${o.orderNumber}',
          subtitle: '${Formatters.currency(o.grandTotal)} · ${o.paymentMethod} · $ago',
        ));
      } else if (o.status == 'ready') {
        notices.add(HomeNotice(
          icon: Icons.done_all_rounded,
          color: AppColors.info,
          title: 'Order #${o.orderNumber} is ready to serve',
          subtitle: '${o.tableName ?? o.itemsSummary} · $ago',
          unread: true,
        ));
      } else if (o.status != 'voided') {
        notices.add(HomeNotice(
          icon: o.orderSource == 'qr' ? Icons.qr_code_2_rounded : Icons.receipt_long_rounded,
          color: AppColors.primary,
          title: o.orderSource == 'qr' ? 'New QR order #${o.orderNumber}' : 'New order #${o.orderNumber}',
          subtitle: '${o.tableName != null ? '${o.tableName} · ' : ''}${o.itemsSummary} · $ago',
          unread: o.orderSource == 'qr',
        ));
      }
    }
    return notices;
  }
}

Future<void> showNotificationsSheet(BuildContext context, List<HomeNotice> notices) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .75),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                  if (notices.any((n) => n.unread))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
                      child: Text('${notices.where((n) => n.unread).length} new',
                          style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            if (notices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Text('🔔', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text('All caught up!', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: notices.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider, indent: 64),
                  itemBuilder: (_, i) {
                    final n = notices[i];
                    return ListTile(
                      onTap: n.onTap == null
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              n.onTap!();
                            },
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: n.color.withValues(alpha: .12), shape: BoxShape.circle),
                        child: Icon(n.icon, color: n.color, size: 20),
                      ),
                      title: Text(n.title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      subtitle: Text(n.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      trailing: n.unread
                          ? Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle))
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
