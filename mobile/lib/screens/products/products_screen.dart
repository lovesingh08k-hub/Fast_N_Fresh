import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_config.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/catalog_service.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with WidgetsBindingObserver {
  final _productService = ProductService();
  final _categoryService = CategoryService();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  List<Category> _categories = [];
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
      final results = await Future.wait([_productService.list(search: _searchController.text.trim()), _categoryService.list()]);
      setState(() {
        _products = results[0] as List<Product>;
        _categories = results[1] as List<Category>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Product? product}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product, categories: _categories)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete product?'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _productService.delete(product.id);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Products')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), child: Icon(Icons.add)),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search products…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: IconButton(icon: Icon(Icons.search, size: 18), onPressed: _load),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _products.isEmpty
                        ? EmptyState(icon: Icons.fastfood_outlined, title: 'No products yet', subtitle: 'Tap + to add your first product.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: _products.length,
                              separatorBuilder: (_, __) => SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = _products[i];
                                return _ProductTile(product: p, onTap: () => _openForm(product: p), onDelete: () => _deleteProduct(p));
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  _ProductTile({required this.product, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.hasImage
                ? Image.network(
                    ApiConfig.resolveAssetUrl(product.imageUrl),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    // Same reasoning as the POS grid tile: avoid decoding a
                    // multi-megapixel upload just to shrink it to 52px.
                    cacheWidth: 52 * 3,
                    cacheHeight: 52 * 3,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(product.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  if (!product.isAvailable)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('Unavailable', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                    ),
                ]),
                SizedBox(height: 4),
                Text(product.categoryName ?? '', style: Theme.of(context).textTheme.bodyMedium),
                SizedBox(height: 4),
                Row(children: [
                  Text(Formatters.currency(product.sellingPrice), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  if (product.trackInventory) ...[
                    SizedBox(width: 10),
                    Text('Stock: ${product.stock}', style: TextStyle(fontSize: 12, color: product.isLowStock ? AppColors.warning : AppColors.textMuted, fontWeight: product.isLowStock ? FontWeight.w700 : FontWeight.w400)),
                  ],
                ]),
              ],
            ),
          ),
          IconButton(icon: Icon(Icons.delete_outline, color: AppColors.danger, size: 20), onPressed: onDelete),
        ]),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 52,
      height: 52,
      color: AppColors.background,
      child: Icon(Icons.fastfood_outlined, color: AppColors.textMuted, size: 22),
    );
  }
}
