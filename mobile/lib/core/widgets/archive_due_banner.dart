import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../screens/settings/archive_screen.dart';
import '../../services/archive_service.dart';
import '../theme/app_colors.dart';

/// Admin reminder (every ~4 months, or when storage runs low) to download
/// old records and clean them off the server. Hidden when nothing is due.
class ArchiveDueBanner extends StatefulWidget {
  const ArchiveDueBanner({super.key});

  @override
  State<ArchiveDueBanner> createState() => _ArchiveDueBannerState();
}

class _ArchiveDueBannerState extends State<ArchiveDueBanner> {
  ArchiveStatus? _status;

  @override
  void initState() {
    super.initState();
    if (context.read<AuthProvider>().isAdmin) _check();
  }

  Future<void> _check() async {
    try {
      final status = await ArchiveService().status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Best-effort reminder; never block the dashboard.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || !s.due) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppColors.warning.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArchiveScreen()));
            _check();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.storageLow
                        ? 'Storage ${s.percent}% full — back up and clean old data'
                        : 'Time to back up old data (${s.oldOrders} old bills)',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.warning),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
