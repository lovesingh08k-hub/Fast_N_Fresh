import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../core/utils/pos_debug_log.dart';
import '../pos/direct_order_screen.dart';
import 'table_detail_screen.dart';
import 'table_form_screen.dart';
import 'qr_management_screen.dart';

/// Shopto-inspired dine-in overview:
/// - Order Channels section
/// - Dining Tables grid
/// - live order/item counts
/// - add/rename/delete/QR actions
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> with WidgetsBindingObserver {
  final TableService _service = TableService();
  List<CafeTable> _tables = [];
  bool _loading = true;
  String? _error;
  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  bool get _canManage => context.read<AuthProvider>().currentUser?.canManageTables ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTables();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connectivity = context.read<ConnectivityProvider>();
    if (!identical(connectivity, _connectivity)) {
      _connectivity?.removeListener(_handleConnectivityChange);
      _connectivity = connectivity;
      _wasOnline = connectivity.isOnline;
      _connectivity!.addListener(_handleConnectivityChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;
    final returned = state == AppLifecycleState.resumed && wasBackgrounded;
    _lastLifecycleState = state;
    if (returned && mounted) _loadTables();
  }

  void _handleConnectivityChange() {
    final online = _connectivity?.isOnline ?? true;
    if (online && !_wasOnline) _loadTables();
    _wasOnline = online;
  }

  Future<void> _loadTables() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final tables = await _service.list();
      if (!mounted) return;
      setState(() { _tables = tables; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load tables. Please try again.'; _loading = false; });
    }
  }

  Future<void> _addTable() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TableFormScreen()),
    );
    if (saved == true) _loadTables();
  }

  Future<void> _showTableQr(CafeTable table) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QrManagementScreen(focusTableId: table.id)),
    );
    if (mounted) _loadTables();
  }

  Future<void> _clearTableOrders(CafeTable table) async {
    if (table.openOrderCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No open orders on this table.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Orders'),
        content: Text('Cancel all ${table.openOrderCount} open order(s) on ${table.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Orders')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.clearAllOrders(table.id);
      await _loadTables();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('All orders cleared from ${table.name}.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not clear orders.')));
    }
  }

  Future<void> _renameTable(CafeTable table) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TableFormScreen(table: table)),
    );
    if (saved == true && mounted) _loadTables();
  }

  Future<void> _deleteTable(CafeTable table) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text(
          table.openOrderCount > 0
              ? '${table.name} has ${table.openOrderCount} open order(s). Delete it anyway?'
              : 'Delete ${table.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.delete(table.id);
      await _loadTables();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${table.name} deleted.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete table.')));
    }
  }

  Future<void> _openTable(CafeTable table) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TableDetailScreen(tableId: table.id)),
    );
    if (mounted) _loadTables();
  }

  Future<void> _openChannel(String type) async {
    posLog('Selected channel: $type');
    if (type == 'dine_in') {
      return _openDiningTables();
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DirectOrderScreen(orderType: type)),
    );
  }

  Future<void> _openDiningTables() async {
    if (_tables.isEmpty) {
      if (_canManage) {
        await _addTable();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No dining tables are configured yet.')),
        );
      }
      return;
    }

    // The Dine-in channel is a real table-selection entry point. Do not
    // silently do nothing: let the cashier choose the table, then continue
    // into the table's Order -> KOT -> Serve -> Pay flow.
    final selected = await showModalBottomSheet<CafeTable>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          height: MediaQuery.of(sheetContext).size.height * .72,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Dining Table', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _tables.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final table = _tables[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
                      tileColor: AppColors.surface,
                      leading: Icon(Icons.table_restaurant_outlined, color: table.isOccupied ? AppColors.warning : AppColors.primary),
                      title: Text(table.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(table.isOccupied ? '${table.openItemCount} items • ${table.openOrderCount} active order(s)' : 'Available for a new dine-in order'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, table),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _openTable(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tables'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'QR Management',
              icon: Icon(Icons.qr_code_2_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => QrManagementScreen()),
                );
                if (mounted) _loadTables();
              },
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh),
            onPressed: _loading ? null : _loadTables,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTables,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tables.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tables.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 16),
          const Center(child: Text('Could not load tables', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))),
          const SizedBox(height: 20),
          Center(child: ElevatedButton.icon(onPressed: _loadTables, icon: Icon(Icons.refresh), label: const Text('Try Again'))),
        ],
      );
    }

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _sectionCard(
              title: 'Order Channels',
              icon: Icons.public,
              child: _channelCard(),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Dining Tables',
              icon: Icons.table_restaurant_outlined,
              trailing: _canManage
                  ? OutlinedButton.icon(
                      onPressed: _addTable,
                      icon: Icon(Icons.add, size: 18),
                      label: const Text('Add Table'),
                    )
                  : null,
              child: _tables.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text('No tables found.', style: TextStyle(color: AppColors.textMuted)),
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _tables.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 330,
                        mainAxisExtent: 154,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (_, i) => _TableCard(
                        table: _tables[i],
                        canManage: _canManage,
                        onTap: () => _openTable(_tables[i]),
                        onShowQr: () => _showTableQr(_tables[i]),
                        onClearOrders: () => _clearTableOrders(_tables[i]),
                        onRename: () => _renameTable(_tables[i]),
                        onDelete: () => _deleteTable(_tables[i]),
                      ),
                    ),
            ),
          ],
        ),
        if (_loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(0, 3), color: Color(0x0A000000))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 25),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _channelCard() {
    // Standalone POS/Default channel is intentionally not exposed here.
    // Takeaway and Delivery are explicit order channels; Dine-in goes through
    // table selection and then the normal Order -> KOT -> Serve -> Pay flow.
    final channels = [
      ('Dine-in', 'Dining tables + KOT', 'dine_in', Icons.table_restaurant_outlined),
      ('Takeaway', 'Counter order', 'takeaway', Icons.shopping_bag_outlined),
      ('Delivery', 'Customer delivery order', 'delivery', Icons.delivery_dining_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? 4 : width >= 560 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: channels.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 82,
          ),
          itemBuilder: (_, index) {
            final channel = channels[index];
            return InkWell(
              onTap: () => _openChannel(channel.$3),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(channel.$4, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(channel.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(channel.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.primary),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  final CafeTable table;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onShowQr;
  final VoidCallback onClearOrders;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TableCard({
    required this.table,
    required this.canManage,
    required this.onTap,
    required this.onShowQr,
    required this.onClearOrders,
    required this.onRename,
    required this.onDelete,
  });

  Color get _statusColor {
    if (table.isOccupied) return AppColors.primary;
    if (table.isReserved) return AppColors.warning;
    return AppColors.success;
  }

  String get _statusText {
    if (table.isOccupied) return '${table.openOrderCount} Customer${table.openOrderCount == 1 ? '' : 's'}';
    if (table.isReserved) return 'Reserved';
    return 'No orders';
  }

  String _ageText() {
    final at = table.latestOpenOrderAt;
    if (at == null) return '';
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'}';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Show QR Code'),
              onTap: () {
                Navigator.pop(sheetContext);
                onShowQr();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear All Orders'),
              onTap: () {
                Navigator.pop(sheetContext);
                onClearOrders();
              },
            ),
            if (canManage)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename Table'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRename();
                },
              ),
            if (canManage)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete Table'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: table.isOccupied ? AppColors.primaryLight.withValues(alpha: .32) : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: table.isOccupied ? _statusColor.withValues(alpha: .35) : AppColors.border,
            width: table.isOccupied ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusText,
                    style: TextStyle(color: _statusColor, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _showMenu(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(Icons.more_horiz, size: 20, color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (table.isOccupied)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '${table.openItemCount} Item${table.openItemCount == 1 ? '' : 's'}',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${table.openOrderCount} active order${table.openOrderCount == 1 ? '' : 's'}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  if (_ageText().isNotEmpty)
                    Text(_ageText(), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              )
            else
              Row(
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(_statusText, style: TextStyle(color: _statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(child: Text('Seats ${table.capacity}', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                if (table.hasQrNumber) Icon(Icons.qr_code_2, size: 16, color: AppColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
