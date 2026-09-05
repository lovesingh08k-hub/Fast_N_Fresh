import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../models/table.dart';
import '../../models/misc_models.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/table_service.dart';
import '../../services/misc_services.dart';
import '../../services/qr_service.dart';

/// Lets Admin/Manager assign each table's QR ordering number and
/// view/print/share the QR code that encodes its public /menu?table=N URL.
class QrManagementScreen extends StatefulWidget {
  QrManagementScreen({super.key});

  @override
  State<QrManagementScreen> createState() => _QrManagementScreenState();
}

class _QrManagementScreenState extends State<QrManagementScreen> with WidgetsBindingObserver {
  final TableService _tableService = TableService();
  final SettingsService _settingsService = SettingsService();

  List<CafeTable> _tables = [];
  BusinessSettings _settings = BusinessSettings();
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
      final results = await Future.wait([_tableService.list(), _settingsService.get()]);
      if (!mounted) return;
      setState(() {
        _tables = results[0] as List<CafeTable>;
        _settings = results[1] as BusinessSettings;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load tables.';
        _loading = false;
      });
    }
  }

  Future<void> _assignNumber(CafeTable table) async {
    final controller = TextEditingController(text: table.number?.toString() ?? '');
    bool cancelled = true;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('QR number for ${table.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Number',
            helperText: 'Customers will scan a code linking to /menu?table=N',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              cancelled = false;
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (cancelled || !mounted) return;

    final text = controller.text.trim();
    if (text.isNotEmpty && int.tryParse(text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a whole number, or leave it blank to remove the QR number.')),
      );
      return;
    }
    final result = text.isEmpty ? null : int.parse(text);

    try {
      await _tableService.setQrNumber(table.id, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result == null ? 'QR number removed.' : 'QR number set to $result.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openQrSheet(CafeTable table) async {
    if (!table.hasQrNumber) {
      await _assignNumber(table);
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QrSheet(table: table, tableService: _tableService, cafeName: _settings.cafeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('QR Management')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tables.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tables.isEmpty) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(24),
        children: [
          SizedBox(height: 80),
          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          SizedBox(height: 12),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
          SizedBox(height: 16),
          Center(child: ElevatedButton(onPressed: _load, child: Text('Try Again'))),
        ],
      );
    }

    return ListView.separated(
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(16),
      itemCount: _tables.length,
      separatorBuilder: (_, __) => SizedBox(height: 10),
      itemBuilder: (context, index) {
        final table = _tables[index];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: table.hasQrNumber ? AppColors.primaryLight : AppColors.divider,
              foregroundColor: table.hasQrNumber ? AppColors.primary : AppColors.textMuted,
              child: Icon(Icons.qr_code_2),
            ),
            title: Text(table.name, style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              table.hasQrNumber ? '/menu?table=${table.number}' : 'No QR number assigned yet',
              style: TextStyle(color: table.hasQrNumber ? AppColors.textSecondary : AppColors.danger),
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Edit number',
                  icon: Icon(Icons.edit_outlined),
                  onPressed: () => _assignNumber(table),
                ),
                IconButton(
                  tooltip: table.hasQrNumber ? 'View QR' : 'Assign a number first',
                  icon: Icon(Icons.visibility_outlined),
                  onPressed: () => _openQrSheet(table),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QrSheet extends StatefulWidget {
  final CafeTable table;
  final TableService tableService;
  final String cafeName;
  _QrSheet({required this.table, required this.tableService, this.cafeName = 'Fast N Fresh Cafe'});

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  final QrService _qrService = QrService();
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.tableService.fetchQrImageBytes(widget.table.id);
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(bytes);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.table.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('/menu?table=${widget.table.number}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 16),
            SizedBox(
              height: 220,
              width: 220,
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger)))
                      : Image.memory(_bytes!, fit: BoxFit.contain),
            ),
            SizedBox(height: 20),
            if (_bytes != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _runBusy(() => _qrService.printQrFlyer(widget.table, _bytes!, cafeName: widget.cafeName)),
                      icon: Icon(Icons.print, size: 20),
                      label: Text('Print'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _runBusy(() => _qrService.shareQrFlyer(widget.table, _bytes!, cafeName: widget.cafeName)),
                      icon: Icon(Icons.download_outlined),
                      label: Text('Download / Share'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
