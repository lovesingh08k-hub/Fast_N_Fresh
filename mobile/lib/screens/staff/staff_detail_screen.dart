import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/dashboard_models.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';

class StaffDetailScreen extends StatefulWidget {
  final String staffId;
  StaffDetailScreen({super.key, required this.staffId});

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> with WidgetsBindingObserver {
  final _service = StaffService();
  StaffPerformance? _performance;
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
      final performance = await _service.getDetail(widget.staffId);
      setState(() => _performance = performance);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load staff details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus() async {
    final staff = _performance!.staff;
    final newStatus = staff.status == 'active' ? 'inactive' : 'active';
    try {
      await _service.update(staff.id, {'status': newStatus});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Password'),
        content: TextField(controller: controller, obscureText: true, decoration: InputDecoration(labelText: 'New Password')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || controller.text.length < 6) return;

    try {
      await _service.resetPassword(widget.staffId, controller.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset successfully.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_performance?.staff.name ?? 'Staff')),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final p = _performance!;
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Container(
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryLight,
                child: Text(p.staff.name.isNotEmpty ? p.staff.name[0].toUpperCase() : '?', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 22)),
              ),
              SizedBox(height: 10),
              Text(p.staff.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text('Staff', style: TextStyle(color: AppColors.textMuted)),
              SizedBox(height: 4),
              Text(p.staff.phone, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                children: [
                  Text(Formatters.currency(p.todaySales), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary)),
                  SizedBox(height: 4),
                  Text("Today's Sales", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                children: [
                  Text('${p.todayBills}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  SizedBox(height: 4),
                  Text('Bills Today', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ]),
        SizedBox(height: 20),
        OutlinedButton.icon(onPressed: _resetPassword, icon: Icon(Icons.lock_reset, size: 18), label: Text('Reset Password')),
        SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _toggleStatus,
          icon: Icon(p.staff.status == 'active' ? Icons.block : Icons.check_circle_outline, size: 18, color: p.staff.status == 'active' ? AppColors.danger : AppColors.success),
          label: Text(
            p.staff.status == 'active' ? 'Deactivate Staff' : 'Activate Staff',
            style: TextStyle(color: p.staff.status == 'active' ? AppColors.danger : AppColors.success),
          ),
          style: OutlinedButton.styleFrom(side: BorderSide(color: p.staff.status == 'active' ? AppColors.danger : AppColors.success)),
        ),
      ],
    );
  }
}
