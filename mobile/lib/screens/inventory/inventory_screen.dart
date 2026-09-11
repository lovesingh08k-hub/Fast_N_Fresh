import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/product.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/inventory_service.dart';

class InventoryScreen extends StatefulWidget {
  InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with WidgetsBindingObserver {
  final _service = InventoryService();
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  bool _lowStockOnly = false;

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
      final (products, _) = await _service.getInventory();
      setState(() => _products = products);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load inventory.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _adjustStock(Product product) async {
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    String type = 'STOCK_IN';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
                SizedBox(height: 16),
                Text('Adjust Stock — ${product.name}', style: Theme.of(context).textTheme.titleLarge),
                Text('Current stock: ${product.stock}', style: Theme.of(context).textTheme.bodyMedium),
                SizedBox(height: 16),
                Row(children: [
                  Expanded(child: ChoiceChip(label: Text('Stock In'), selected: type == 'STOCK_IN', onSelected: (_) => setModalState(() => type = 'STOCK_IN'))),
                  SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: Text('Stock Out'), selected: type == 'STOCK_OUT', onSelected: (_) => setModalState(() => type = 'STOCK_OUT'))),
                  SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: Text('Adjust'), selected: type == 'ADJUSTMENT', onSelected: (_) => setModalState(() => type = 'ADJUSTMENT'))),
                ]),
                SizedBox(height: 14),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.numberWithOptions(signed: true),
                  decoration: InputDecoration(labelText: type == 'ADJUSTMENT' ? 'Quantity (+/-)' : 'Quantity'),
                ),
                SizedBox(height: 12),
                TextField(controller: reasonController, decoration: InputDecoration(labelText: 'Reason (optional)')),
                SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () async {
                    final qty = int.tryParse(qtyController.text);
                    if (qty == null || qty == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter a valid quantity.')));
                      return;
                    }
                    try {
                      await _service.adjust(productId: product.id, type: type, quantity: qty, reason: reasonController.text.trim());
                      if (context.mounted) Navigator.pop(context, true);
                    } on ApiException catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: Text('Save Adjustment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _lowStockOnly ? _products.where((p) => p.isLowStock).toList() : _products;

    return Scaffold(
      appBar: AppBar(title: Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              FilterChip(
                label: Text('Low Stock Only'),
                selected: _lowStockOnly,
                onSelected: (v) => setState(() => _lowStockOnly = v),
                selectedColor: AppColors.warning,
                labelStyle: TextStyle(color: _lowStockOnly ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : displayed.isEmpty
                        ? EmptyState(icon: Icons.inventory_2_outlined, title: 'Nothing to show', subtitle: 'No products match this filter.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: displayed.length,
                              separatorBuilder: (_, __) => SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = displayed[i];
                                return InkWell(
                                  onTap: () => _adjustStock(p),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name, style: TextStyle(fontWeight: FontWeight.w700)),
                                            SizedBox(height: 3),
                                            Text('Stock: ${p.stock}', style: Theme.of(context).textTheme.bodyMedium),
                                          ],
                                        ),
                                      ),
                                      if (p.isLowStock)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                                            SizedBox(width: 4),
                                            Text('Low Stock', style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                                          ]),
                                        ),
                                      SizedBox(width: 8),
                                      Icon(Icons.chevron_right, color: AppColors.textMuted),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
