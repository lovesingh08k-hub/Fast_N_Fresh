import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';
import 'staff_attendance_detail_screen.dart';

/// Admin-only. Shows which employee attended/handled each customer, across
/// Dine-In, Takeaway, and Delivery — never visible to Manager or Staff.
class AttendanceScreen extends StatefulWidget {
  AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with WidgetsBindingObserver {
  final _service = AttendanceService();
  List<dynamic> _summary = [];
  bool _loading = true;
  String? _error;
  String _range = 'Today';

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

  DateTime? get _from {
    final now = DateTime.now();
    switch (_range) {
      case 'Today':
        return DateTime(now.year, now.month, now.day);
      case 'This Week':
        return now.subtract(Duration(days: now.weekday % 7));
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _service.getSummary(from: _from);
      setState(() => _summary = summary);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load staff performance data.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Staff Performance')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: ['Today', 'This Week', 'This Month', 'All Time'].map((label) {
                final selected = _range == label;
                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _range = label);
                      _load();
                    },
                    labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _summary.isEmpty
                        ? EmptyState(icon: Icons.leaderboard_outlined, title: 'No activity in this period')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.all(16),
                              itemCount: _summary.length,
                              separatorBuilder: (_, __) => SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final s = _summary[i] as Map<String, dynamic>;
                                return _StaffPerformanceTile(data: s, from: _from);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StaffPerformanceTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime? from;
  _StaffPerformanceTile({required this.data, required this.from});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StaffAttendanceDetailScreen(staffId: data['staffId'] as String, staffName: data['name'] as String? ?? '', from: from)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(data['name'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              Text(Formatters.currency((data['sales'] as num?) ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ]),
            SizedBox(height: 8),
            Row(children: [
              _statChip('${data['customersAttended'] ?? 0} customers'),
              SizedBox(width: 8),
              _statChip('${data['ordersHandled'] ?? 0} orders'),
              SizedBox(width: 8),
              _statChip('${data['creditTransactionsCreated'] ?? 0} credits'),
            ]),
            SizedBox(height: 8),
            Text(
              'Dine-In: ${data['dineIn'] ?? 0}   Takeaway: ${data['takeaway'] ?? 0}   Delivery: ${data['delivery'] ?? 0}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}
