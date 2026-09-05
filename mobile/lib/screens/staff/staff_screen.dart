import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/user.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';
import 'staff_form_screen.dart';
import 'staff_detail_screen.dart';

class StaffScreen extends StatefulWidget {
  StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> with WidgetsBindingObserver {
  final _service = StaffService();
  List<AppUser> _staff = [];
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
      final staff = await _service.list();
      setState(() => _staff = staff);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load staff.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Staff')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StaffFormScreen()));
          if (saved == true) _load();
        },
        child: Icon(Icons.person_add_alt),
      ),
      body: _loading
          ? LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _staff.isEmpty
                  ? EmptyState(icon: Icons.badge_outlined, title: 'No staff members yet', subtitle: 'Tap + to add your first staff member.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: _staff.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = _staff[i];
                          return InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffDetailScreen(staffId: s.id)));
                              _load();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                              child: Row(children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.primaryLight,
                                  child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: TextStyle(fontWeight: FontWeight.w700)),
                                      SizedBox(height: 2),
                                      Text('@${s.username}', style: Theme.of(context).textTheme.bodyMedium),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (s.status == 'active' ? AppColors.success : AppColors.textMuted).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    s.status == 'active' ? 'Active' : 'Inactive',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.status == 'active' ? AppColors.success : AppColors.textMuted),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(Icons.chevron_right, color: AppColors.textMuted),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
