import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_widgets.dart';
import '../../services/archive_service.dart';

/// Admin: keeps the database small. Old bills and records are downloaded
/// (full JSON backup + Excel-ready bills sheet), then deleted from the
/// server; a total per day stays so old sales are still visible.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _service = ArchiveService();

  ArchiveStatus? _status;
  List<DaySummary> _summaries = const [];
  String? _error;
  bool _loading = true;
  String? _busy; // which action is running

  /// Cut-off date (YYYY-MM-DD) and whether its backup was downloaded here.
  String? _before;
  bool _backupSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.status();
      final summaries = await _service.summaries();
      if (!mounted) return;
      setState(() {
        _status = status;
        _summaries = summaries;
        _before ??= status.suggestedBefore;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load storage details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final status = _status;
    if (status == null) return;
    final latest = DateTime.parse(status.suggestedBefore);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_before ?? '') ?? latest,
      firstDate: DateTime(2020),
      lastDate: latest,
      helpText: 'Archive records before',
    );
    if (picked == null) return;
    setState(() {
      _before = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _backupSaved = false;
    });
  }

  Future<void> _download({required bool csv}) async {
    final before = _before;
    if (before == null) return;
    setState(() => _busy = csv ? 'csv' : 'json');
    try {
      final bytes = await _service.download(before: before, csv: csv);
      final name = 'pos-backup-before-$before${csv ? '-bills.csv' : '.json'}';
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: name, mimeType: csv ? 'text/csv' : 'application/json')],
        fileNameOverrides: [name],
        subject: name,
      );
      if (!mounted) return;
      if (!csv) setState(() => _backupSaved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(csv ? 'Bills sheet ready — save it to Drive or Files.' : 'Backup ready — keep this file safe (Drive, email or PC).')),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the file. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _purge() async {
    final before = _before;
    if (before == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete old records?'),
        content: Text(
          'Bills, payments, expenses and logs from before $before will be removed from the server. '
          'You have downloaded the backup; day-wise sales totals stay in the app. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = 'purge');
    try {
      final result = await _service.purge(before);
      if (!mounted) return;
      final deleted = (result['deleted'] as Map?)?['orders'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$deleted old bills removed. Storage freed.')));
      setState(() => _backupSaved = false);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & Storage'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading && _status == null
          ? const LoadingState()
          : _error != null && _status == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final s = _status!;
    final percent = (s.percent ?? 0).clamp(0, 100);
    final barColor = percent >= 85 ? AppColors.danger : percent >= 70 ? AppColors.warning : AppColors.primary;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (s.due) _dueBanner(s),
        _card(
          title: 'Storage',
          icon: Icons.storage_rounded,
          children: [
            if (s.usedMB != null) ...[
              Text('${s.usedMB!.toStringAsFixed(1)} MB of ${s.limitMB!.toStringAsFixed(0)} MB used ($percent%)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: percent / 100, minHeight: 8, color: barColor, backgroundColor: AppColors.border),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              s.lastArchiveAt == null
                  ? 'Never archived yet. Archive every ${s.everyDays ~/ 30} months to keep the app fast.'
                  : 'Last archived ${Formatters.date(s.lastArchiveAt!)}. Next reminder after ${s.everyDays} days.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _card(
          title: 'Archive old records',
          icon: Icons.inventory_2_outlined,
          children: [
            Text(
              'The last ${s.keepRecentDays} days always stay. Older bills, payments, expenses and logs can be '
              'downloaded to your phone/PC and then removed from the server. Customers, menu, tables and staff are never removed.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy != null ? null : _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Records before: ${_before ?? '-'}'),
            ),
            const SizedBox(height: 12),
            Text('1. Download', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy != null ? null : () => _download(csv: false),
                  icon: _busy == 'json' ? _spinner() : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Full backup (JSON)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy != null ? null : () => _download(csv: true),
                  icon: _busy == 'csv' ? _spinner() : const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Bills for Excel (CSV)'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('2. Delete from server', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _busy != null || !_backupSaved ? null : _purge,
              icon: _busy == 'purge' ? _spinner() : const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Delete archived records'),
            ),
            if (!_backupSaved)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Download the full backup first.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
          ],
        ),
        if (_summaries.isNotEmpty) ...[
          const SizedBox(height: 14),
          _card(
            title: 'Archived days',
            icon: Icons.history_rounded,
            children: [
              for (final day in _summaries.take(60))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(day.date)),
                      Text('${day.orders} bills', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      const SizedBox(width: 14),
                      Text(Formatters.currency(day.netSales), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dueBanner(ArchiveStatus s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(Icons.notification_important_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.storageLow
                  ? 'Storage is getting full. Download and clean up ${s.oldOrders} old bills now.'
                  : 'Time for your ${s.everyDays ~/ 30}-monthly backup: ${s.oldOrders} old bills can be archived.',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _card({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
