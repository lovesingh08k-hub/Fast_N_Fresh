import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';

class StaffAttendanceDetailScreen extends StatefulWidget {
  final String staffId;
  final String staffName;
  final DateTime? from;

  StaffAttendanceDetailScreen({super.key, required this.staffId, required this.staffName, this.from});

  @override
  State<StaffAttendanceDetailScreen> createState() => _StaffAttendanceDetailScreenState();
}

class _StaffAttendanceDetailScreenState extends State<StaffAttendanceDetailScreen> with WidgetsBindingObserver {
  final _service = AttendanceService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
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

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    if (returnedToForeground && mounted && _error != null) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && _error != null) {
      _load();
    }

    _wasOnline = isOnline;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getStaffDetail(widget.staffId, from: widget.from);
      setState(() => _data = data);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load staff activity.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.staffName} — Activity')),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final summary = _data!['summary'] as Map<String, dynamic>;
    final orders = _data!['orders'] as List<dynamic>;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              _row('Customers Attended', '${summary['customersAttended'] ?? 0}'),
              _row('Orders Handled', '${summary['ordersHandled'] ?? 0}'),
              _row('Total Sales', Formatters.currency((summary['sales'] as num?) ?? 0)),
              Divider(height: 20),
              _row('Dine-In', '${summary['dineIn'] ?? 0}'),
              _row('Takeaway', '${summary['takeaway'] ?? 0}'),
              _row('Delivery', '${summary['delivery'] ?? 0}'),
            ],
          ),
        ),
        SizedBox(height: 20),
        Text('Orders', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 10),
        if (orders.isEmpty)
          Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('No orders in this period.', style: TextStyle(color: AppColors.textMuted))))
        else
          ...orders.map((o) {
            final order = o as Map<String, dynamic>;
            final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '') ?? DateTime.now();
            return Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${order['orderNumber']}  ${order['customerName'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text(
                        '${_typeLabel(order['orderType'] as String?)}${order['table'] != null ? ' · Table ${order['table']}' : ''} · ${Formatters.time(createdAt)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(Formatters.currency((order['grandTotal'] as num?) ?? 0), style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
            );
          }),
      ],
    );
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'dine_in':
        return 'Dine-In';
      case 'delivery':
        return 'Delivery';
      default:
        return 'Takeaway';
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
