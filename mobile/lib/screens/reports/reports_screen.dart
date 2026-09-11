import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_widgets.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/misc_services.dart';

class ReportsScreen extends StatefulWidget {
  // When true (used for Manager access), only the Credit/UDHAR report is
  // shown — Sales/Products/Staff reports remain admin-only and are hidden
  // entirely rather than shown and then rejected by the backend.
  final bool creditOnly;
  ReportsScreen({super.key, this.creditOnly = false});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final _service = ReportService();

  @override
  void initState() {
    super.initState();
    if (!widget.creditOnly) {
      _tabController = TabController(length: 4, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.creditOnly) {
      return Scaffold(
        appBar: AppBar(title: Text('Credit / UDHAR Report')),
        body: _CreditReportTab(service: _service),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [Tab(text: 'Sales'), Tab(text: 'Products'), Tab(text: 'Staff'), Tab(text: 'Credit')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SalesReportTab(service: _service),
          _ProductReportTab(service: _service),
          _StaffReportTab(service: _service),
          _CreditReportTab(service: _service),
        ],
      ),
    );
  }
}

class _SalesReportTab extends StatefulWidget {
  final ReportService service;
  _SalesReportTab({required this.service});

  @override
  State<_SalesReportTab> createState() => _SalesReportTabState();
}

class _SalesReportTabState extends State<_SalesReportTab> with WidgetsBindingObserver {
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
    setState(() => _loading = true);
    try {
      final data = await widget.service.salesReport();
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not load sales report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return LoadingState();
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final d = _data!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _reportCard('Total Sales', Formatters.currency(d['totalSales'] ?? 0), AppColors.primary),
          _reportCard('Number of Orders', '${d['numberOfOrders'] ?? 0}', AppColors.info),
          _reportCard('Average Order Value', Formatters.currency(d['averageOrderValue'] ?? 0), AppColors.accent),
          SizedBox(height: 8),
          _reportCard('Cash', Formatters.currency(d['cash'] ?? 0), AppColors.cash),
          _reportCard('UPI', Formatters.currency(d['upi'] ?? 0), AppColors.upi),
          _reportCard('Credit', Formatters.currency(d['credit'] ?? 0), AppColors.credit),
        ],
      ),
    );
  }
}

class _ProductReportTab extends StatefulWidget {
  final ReportService service;
  _ProductReportTab({required this.service});

  @override
  State<_ProductReportTab> createState() => _ProductReportTabState();
}

class _ProductReportTabState extends State<_ProductReportTab> with WidgetsBindingObserver {
  List<dynamic> _data = [];
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
    setState(() => _loading = true);
    try {
      final data = await widget.service.productReport();
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not load product report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return LoadingState();
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_data.isEmpty) return EmptyState(icon: Icons.bar_chart_outlined, title: 'No sales data yet');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(16),
        itemCount: _data.length,
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (context, i) {
          final p = _data[i] as Map<String, dynamic>;
          return Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${p['quantitySold'] ?? 0} sold', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(Formatters.currency(p['revenue'] ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          );
        },
      ),
    );
  }
}

class _StaffReportTab extends StatefulWidget {
  final ReportService service;
  _StaffReportTab({required this.service});

  @override
  State<_StaffReportTab> createState() => _StaffReportTabState();
}

class _StaffReportTabState extends State<_StaffReportTab> with WidgetsBindingObserver {
  List<dynamic> _data = [];
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
    setState(() => _loading = true);
    try {
      final data = await widget.service.staffReport();
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not load staff report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return LoadingState();
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_data.isEmpty) return EmptyState(icon: Icons.badge_outlined, title: 'No sales data yet');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(16),
        itemCount: _data.length,
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (context, i) {
          final s = _data[i] as Map<String, dynamic>;
          return Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${s['orders'] ?? 0} orders', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(Formatters.currency(s['sales'] ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          );
        },
      ),
    );
  }
}

class _CreditReportTab extends StatefulWidget {
  final ReportService service;
  _CreditReportTab({required this.service});

  @override
  State<_CreditReportTab> createState() => _CreditReportTabState();
}

class _CreditReportTabState extends State<_CreditReportTab> with WidgetsBindingObserver {
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
    setState(() => _loading = true);
    try {
      final data = await widget.service.creditReport();
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not load credit report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return LoadingState();
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final d = _data!;
    final customers = (d['customersWithDue'] as List<dynamic>? ?? []);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _reportCard('Total Outstanding', Formatters.currency(d['totalOutstanding'] ?? 0), AppColors.credit),
          _reportCard('Total Collected', Formatters.currency(d['totalPaymentsCollected'] ?? 0), AppColors.success),
          SizedBox(height: 14),
          Text('Customers with Dues', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          if (customers.isEmpty)
            Text('No outstanding dues.', style: TextStyle(color: AppColors.textMuted))
          else
            ...customers.map((c) {
              final map = c as Map<String, dynamic>;
              return Container(
                margin: EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Expanded(child: Text(map['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600))),
                  Text(Formatters.currency(map['due'] ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.credit)),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

Widget _reportCard(String label, String value, Color color) {
  return Container(
    margin: EdgeInsets.only(bottom: 10),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
      ],
    ),
  );
}
