import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import 'fresh_ui.dart';

/// Business, current outlet and licence status. For a franchise (several
/// outlets) it switches the whole app to another outlet; each outlet has
/// its own bills, customers, tables and menu.
class OutletSwitcherCard extends StatelessWidget {
  const OutletSwitcherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = auth.session;
    if (session == null) return const SizedBox.shrink();

    final outlet = session.currentOutlet;
    final daysLeft = session.daysLeft;
    final expiringSoon = daysLeft != null && daysLeft <= 15;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: session.hasManyOutlets ? () => showOutletPicker(context) : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: FreshUi.card(tint: expiringSoon ? AppColors.warning : FreshUi.mint, tintStrength: expiringSoon ? .08 : 0),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outlet?.name ?? session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        [
                          session.name,
                          if (session.hasManyOutlets) '${session.outlets.length} outlets',
                          if (expiringSoon)
                            daysLeft < 0 ? 'Subscription expired' : 'Subscription ends in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                        ].join(' · '),
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          color: expiringSoon ? AppColors.warning : AppColors.textSecondary,
                          fontWeight: expiringSoon ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.hasManyOutlets)
                  TextButton.icon(
                    onPressed: () => showOutletPicker(context),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Switch'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick an outlet; the app reopens on it.
Future<void> showOutletPicker(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final session = auth.session;
  if (session == null) return;

  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Switch outlet', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
          ),
          for (final outlet in session.outlets)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(outlet.name),
              subtitle: Text(outlet.code),
              trailing: outlet.code == session.currentOutletCode ? Icon(Icons.check_rounded, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(sheetContext, outlet.code),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null || picked == session.currentOutletCode || !context.mounted) return;

  // Leave any open page of the old outlet before the app switches.
  Navigator.of(context).popUntil((route) => route.isFirst);
  await auth.switchOutlet(picked);
}
