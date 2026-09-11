import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/product_image.dart';
import '../../core/widgets/order_flow_stepper.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pos_debug_log.dart';
import '../../models/cart_item.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/tab_refresh_bus.dart';
import 'cart_sheet.dart';
import 'payment_sheet.dart';
import '../tables/tables_screen.dart';
import '../tables/qr_management_screen.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';
import '../../services/order_service.dart';
import '../../core/network/api_exception.dart';

class PosScreen extends StatefulWidget {
  final String? orderType;
  final String? tableId;
  final String? tableName;
  final String? tableCustomerLabel;
  final String? openOrderId;

  /// The existing order's items/discount, when opening an already-placed
  /// Dine-In order for editing. When present, the cart is hydrated with
  /// these instead of starting empty.
  final List<OrderItem>? existingItems;
  final double? existingDiscount;

  /// If true, the cart sheet will open automatically
  /// after the POS screen is displayed.
  final bool autoOpenCart;

  PosScreen({
    super.key,
    this.orderType,
    this.tableId,
    this.tableName,
    this.tableCustomerLabel,
    this.openOrderId,
    this.existingItems,
    this.existingDiscount,
    this.autoOpenCart = false,
  });

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with WidgetsBindingObserver {
  String? _selectedCategoryId;
  late String _orderMode;
  bool _selectingTable = false;
  final TableService _tableService = TableService();

  final TextEditingController _searchController =
      TextEditingController();

  String get _searchQuery =>
      _searchController.text.trim().toLowerCase();

  String get _resolvedOrderType {
    if (widget.orderType != null &&
        widget.orderType!.trim().isNotEmpty) {
      return widget.orderType!;
    }

    if (widget.tableId != null) {
      return 'dine_in';
    }

    return 'takeaway';
  }

  Future<void> _screenAwakeOperation = Future<void>.value();

  void _setScreenAwake(bool enabled) {
    // Serialize platform calls so rapid lifecycle/navigation transitions
    // cannot leave the final wakelock state different from the latest request.
    _screenAwakeOperation = _screenAwakeOperation
        .catchError((_) {})
        .then((_) async {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    posLog(
      'Screen initialized (orderType: ${widget.orderType}, '
      'tableId: ${widget.tableId}, openOrderId: ${widget.openOrderId})',
    );
    _orderMode = widget.tableId != null
        ? 'dine_in'
        : (widget.orderType == 'delivery' ? 'delivery' : 'takeaway');
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    _setScreenAwake(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final catalog = context.read<CatalogProvider>();

      // Always kick the shared catalog once when POS becomes visible.
      // The provider de-duplicates concurrent requests.
      catalog.ensureLoaded();

      context.read<CartProvider>().configureContext(
            orderType: _resolvedOrderType,
            tableId: widget.tableId,
            tableName: widget.tableName,
            tableCustomerLabel: widget.tableCustomerLabel,
            openOrderId: widget.openOrderId,
          );

      if (widget.existingItems != null) {
        context.read<CartProvider>().hydrateFromOpenOrder(
              items: widget.existingItems!
                  .map(
                    (oi) => CartItem(
                      product: Product(
                        id: oi.productId,
                        name: oi.name,
                        categoryId: '',
                        sellingPrice: oi.price,
                        imageUrl: oi.imageUrl,
                      ),
                      quantity: oi.quantity,
                    ),
                  )
                  .toList(),
              discount: widget.existingDiscount ?? 0,
            );
      }

      if (widget.autoOpenCart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openCart();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setScreenAwake(false);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _setScreenAwake(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _setScreenAwake(false);
        break;
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  // Used only to avoid re-logging the same count on every rebuild (this
  // screen repaints on every theme-animation tick via AnimatedBuilder).
  int? _lastLoggedDisplayedCount;

  List<Product> _filteredProducts(
    CatalogProvider catalog,
  ) {
    var products =
        catalog.productsForCategory(_selectedCategoryId);
    final beforeSearchCount = products.length;

    if (_searchQuery.isNotEmpty) {
      products = products.where((product) {
        return product.name
            .toLowerCase()
            .contains(_searchQuery);
      }).toList();
    }

    if (_lastLoggedDisplayedCount != products.length) {
      _lastLoggedDisplayedCount = products.length;
      posLog(
        'Filtered product count: $beforeSearchCount (category: '
        '${_selectedCategoryId ?? 'All'}) -> Final displayed product '
        'count: ${products.length} (search: "$_searchQuery")',
      );
    }

    return products;
  }

  bool get _isFixedOrder =>
      widget.openOrderId != null || widget.tableId != null;

  String get _modeLabel {
    switch (_orderMode) {
      case 'dine_in':
        return 'Dine-in';
      case 'delivery':
        return 'Delivery';
      case 'takeaway':
      default:
        return 'Takeaway';
    }
  }

  Future<void> _changeOrderMode(String mode) async {
    if (_isFixedOrder || mode == _orderMode) return;

    final cart = context.read<CartProvider>();
    if (!cart.isEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new order?'),
          content: const Text(
            'The current cart will be cleared so you can start the new order type.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Cart'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start New'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }

    cart.clear();
    if (!mounted) return;

    setState(() {
      _orderMode = mode;
    });

    if (mode == 'dine_in') {
      await _selectTable();
      if (mounted && context.read<CartProvider>().tableId == null) {
        setState(() => _orderMode = 'takeaway');
        context.read<CartProvider>().configureContext(orderType: 'takeaway');
      }
    } else {
      cart.configureContext(orderType: mode);
    }
  }

  Future<void> _selectTable() async {
    if (_selectingTable || !mounted) return;
    setState(() => _selectingTable = true);

    try {
      final tables = await _tableService.list();
      if (!mounted) return;

      final selected = await showModalBottomSheet<CafeTable>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Dining Table',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                const Text('Choose a free table to start a new order.'),
                const SizedBox(height: 14),
                if (tables.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No dining tables configured.')),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.52,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: tables.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.2,
                      ),
                      itemBuilder: (_, i) {
                        final table = tables[i];
                        final occupied = table.isOccupied || table.openOrderCount > 0;
                        return InkWell(
                          onTap: occupied ? null : () => Navigator.pop(ctx, table),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: occupied
                                  ? AppColors.background
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: occupied
                                    ? AppColors.border
                                    : AppColors.primary.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.table_restaurant_outlined,
                                  color: occupied
                                      ? AppColors.textMuted
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(table.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      Text(
                                        occupied ? 'Occupied' : 'Available',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: occupied ? AppColors.danger : AppColors.credit,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TablesScreen()),
                    );
                  },
                  icon: const Icon(Icons.table_restaurant_outlined),
                  label: const Text('Open Table Management'),
                ),
              ],
            ),
          ),
        ),
      );

      if (selected == null || !mounted) return;

      final started = await _tableService.startOrder(selected.id);
      if (!mounted) return;

      context.read<CartProvider>().configureContext(
            orderType: 'dine_in',
            tableId: selected.id,
            tableName: selected.name,
            openOrderId: started.id,
          );
      setState(() {});
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select table: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _selectingTable = false);
    }
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CartSheet(
        onContinueToPayment: _openPayment,
        onSaveAndSendToKitchen: _saveOrder,
      ),
    );
  }

  Future<void> _saveOrder() async {
    if (!mounted) return;
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      Order order;
      final service = OrderService();

      if (cart.openOrderId == null) {
        order = await service.startOpenOrder(
          orderType: cart.orderType,
          tableId: cart.tableId,
          tableCustomerLabel: cart.tableCustomerLabel,
          customerId: cart.selectedCustomer?.id,
          notes: cart.notes,
          deliveryInfo: cart.orderType == 'delivery'
              ? {
                  'address': cart.deliveryAddress.trim(),
                  'phone': cart.deliveryPhone.trim(),
                }
              : null,
        );

        if (!mounted) return;
        await service.updateOpenOrderItems(
          order.id,
          items: cart.items,
          discount: cart.discount,
          notes: cart.notes,
          customerId: cart.selectedCustomer?.id,
        );

        cart.configureContext(
          orderType: cart.orderType,
          tableId: cart.tableId,
          tableName: cart.tableName,
          tableCustomerLabel: cart.tableCustomerLabel,
          openOrderId: order.id,
        );
      } else {
        await service.updateOpenOrderItems(
          cart.openOrderId!,
          items: cart.items,
          discount: cart.discount,
          notes: cart.notes,
          customerId: cart.selectedCustomer?.id,
        );
        order = await service.getById(cart.openOrderId!);
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Order #${order.orderNumber} saved')),
      );
      context.read<TabRefreshBus>().bumpDashboard();
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Could not save the order. Please try again.')));
    }
  }

  void _openPayment() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaymentSheet(),
    );
  }

  Future<void> _showQuickItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter item name',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price',
                hintText: 'Enter price',
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add to Cart')),
        ],
      ),
    );

    if (result != true || !mounted) {
      nameController.dispose();
      priceController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final price = double.tryParse(priceController.text.trim());
    nameController.dispose();
    priceController.dispose();

    if (name.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid item name and price.')),
      );
      return;
    }

    final product = Product(
      id: 'quick:${Uuid().v4()}',
      name: name,
      categoryId: '',
      sellingPrice: price,
      costPrice: 0,
      trackInventory: false,
      stock: 0,
    );

    context.read<CartProvider>().addProduct(product);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name added to cart')),
      );
    }
  }

  void _closeSheetThen(BuildContext sheetContext, FutureOr<void> Function() next) {
    Navigator.of(sheetContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) next();
    });
  }

  Future<void> _showQrTools() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.qr_code_2),
              title: Text('QR / Table Tools'),
              subtitle: Text('Use table QR management or open a table order.'),
            ),
            ListTile(
              leading: const Icon(Icons.table_restaurant_outlined),
              title: const Text('Open Dining Tables'),
              onTap: () {
                _closeSheetThen(ctx, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TablesScreen()));
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('QR Management'),
              onTap: () {
                _closeSheetThen(ctx, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrManagementScreen()));
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the POS shell independent from catalog state. A catalog/provider
    // failure must never prevent the AppBar, order mode, search or cart UI
    // from painting. Only the catalog subtree listens to CatalogProvider.
    final cart = context.watch<CartProvider>();

    // IMPORTANT: do not wrap the complete POS screen in an AnimatedBuilder
    // driven by the legacy AppColors notifier. The POS is a high-frequency
    // provider-driven screen and the extra animation layer can expose a
    // blank-looking body on some Flutter/release combinations while the
    // AppBar remains mounted. MaterialApp already animates ThemeData; the
    // POS must always paint its workspace directly.
    return _buildScaffold(context, cart);
  }

  Widget _buildScaffold(
    BuildContext context,
    CartProvider cart,
  ) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.tableName != null ? widget.tableName! : 'New Order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _modeLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Quick Item',
            onPressed: _showQuickItem,
            icon: Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'QR / Table',
            onPressed: _showQrTools,
            icon: Icon(Icons.qr_code_2_outlined),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Cart',
                onPressed: _openCart,
                icon: Icon(Icons.shopping_cart_outlined),
              ),
              if (cart.itemCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      '${cart.itemCount}',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      // Keep the POS shell outside the catalog scroll viewport.
      //
      // The previous implementation put the complete POS workspace
      // (mode/search/catalog) into one ListView. If any catalog subtree hit a
      // runtime/layout exception, the whole body could appear white while the
      // AppBar stayed visible. The shell is now a fixed Column and ONLY the
      // catalog area gets its own scrollable viewport.
      // HARDENED POS BODY: one simple scroll viewport. No Expanded or nested
      // catalog viewport can collapse the workspace or turn the release UI
      // into an AppBar-only white screen.
      body: SafeArea(
        top: false,
        child: ListView(
          key: const PageStorageKey<String>('pos-workspace-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (!_isFixedOrder) _buildOrderModeBar(),
            if (widget.tableId != null) ...[
              const OrderFlowStepper(currentStep: 1),
              _buildTableBanner(),
            ] else if (_orderMode == 'dine_in')
              _buildChooseTableBanner(),
            _buildSearch(),
            // Keep provider listening isolated to this one subtree. The POS
            // shell itself never depends on CatalogProvider being in a
            // particular loading/error state.
            Consumer<CatalogProvider>(
              builder: (catalogContext, catalog, _) {
                return _buildCatalogContent(catalogContext, catalog);
              },
            ),
          ],
        ),
      ),

      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        child: cart.itemCount > 0
          ? SafeArea(
              minimum: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12,
              ),
              child: ElevatedButton(
                onPressed: _openCart,
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'View Cart • '
                      '${Formatters.currency(cart.grandTotal)}',
                    ),
                  ],
                ),
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildOrderModeBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('takeaway', Icons.flash_on_outlined, 'Quick Order')),
          Expanded(child: _modeButton('dine_in', Icons.table_restaurant_outlined, 'Dine-in')),
          Expanded(child: _modeButton('delivery', Icons.delivery_dining_outlined, 'Delivery')),
        ],
      ),
    );
  }

  Widget _modeButton(
    String mode,
    IconData icon,
    String label,
  ) {
    final selected = _orderMode == mode;
    return InkWell(
      onTap: () => _changeOrderMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChooseTableBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.table_restaurant_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Dine-in selected. Pick a table before adding items.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            onPressed: _selectTable,
            child: const Text('Select Table'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBanner() {
    return Container(
      margin: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        0,
      ),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.table_restaurant_outlined,
            color: AppColors.primary,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tableName ??
                      'Dine-In Table',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                if (widget.tableCustomerLabel != null &&
                    widget.tableCustomerLabel!
                        .trim()
                        .isNotEmpty)
                  Text(
                    widget.tableCustomerLabel!,
                    style: TextStyle(
                      color:
                          AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),

                if (widget.openOrderId != null)
                  Text(
                    'Existing open order',
                    style: TextStyle(
                      color: AppColors.credit,
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        8,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) {},
        decoration: InputDecoration(
          hintText: 'Search food items...',
          prefixIcon: Icon(
            Icons.search,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();

                        setState(() {});
                      },
                      icon: Icon(
                        Icons.clear,
                      ),
                    )
                  : null,
        ),
      ),
    );
  }

  Widget _buildCategories(
    CatalogProvider catalog,
  ) {
    if (catalog.categories.isEmpty) {
      return const SizedBox(height: 8);
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding:
            EdgeInsets.symmetric(
          horizontal: 16,
        ),
        scrollDirection: Axis.horizontal,
        itemCount:
            catalog.categories.length + 1,
        separatorBuilder: (_, __) =>
            SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _categoryChip(
              label: 'All',
              selected:
                  _selectedCategoryId == null,
              onTap: () {
                setState(() {
                  _selectedCategoryId = null;
                });
              },
            );
          }

          final category =
              catalog.categories[index - 1];

          return _categoryChip(
            label: category.name,
            selected:
                _selectedCategoryId ==
                    category.id,
            onTap: () {
              setState(() {
                _selectedCategoryId =
                    category.id;
              });
            },
          );
        },
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor:
          AppColors.primaryLight,
      labelStyle: TextStyle(
        color: selected
            ? AppColors.primary
            : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.primary
            : AppColors.border,
      ),
    );
  }

  Widget _buildCatalogContent(
    BuildContext context,
    CatalogProvider catalog,
  ) {
    try {
      if (catalog.isLoading && catalog.products.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Menu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 14),
              Text('Loading food items…', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              const _ProductSkeletonGrid(),
            ],
          ),
        );
      }

      if (catalog.errorMessage != null && catalog.products.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: _PosStateMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Menu unavailable',
            message: catalog.errorMessage!,
            actionLabel: 'Retry Menu',
            onAction: catalog.load,
            danger: true,
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (catalog.categories.isNotEmpty) _buildCategories(catalog),
          _buildProductWorkspace(catalog),
        ],
      );
    } catch (e, stack) {
      posLog('Catalog content build failed: $e\n$stack');
      return _buildCatalogFailureState(context, e);
    }
  }

  Widget _buildPosBodyFailure(BuildContext context, Object error) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        _PosStateMessage(
          icon: Icons.warning_amber_rounded,
          title: 'POS could not be displayed',
          message: 'Something prevented the order workspace from rendering. Retry the screen.',
          actionLabel: 'Retry',
          onAction: () {
            posLog('Manual POS body retry after build error: $error');
            if (mounted) setState(() {});
            context.read<CatalogProvider>().load();
          },
          danger: true,
        ),
      ],
    );
  }

  Widget _buildCatalogScroll(
    BuildContext context,
    CatalogProvider catalog,
  ) {
    // This viewport owns ONLY the catalog. Search, order mode and action
    // controls live outside it, so a catalog failure can never make the whole
    // POS body disappear.
    return ListView(
      key: const PageStorageKey<String>('pos-catalog-scroll'),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (catalog.categories.isNotEmpty) _buildCategories(catalog),
        _buildProductWorkspace(catalog),
      ],
    );
  }

  Widget _buildCatalogFailureState(BuildContext context, Object error) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: _PosStateMessage(
        icon: Icons.warning_amber_rounded,
        title: 'Menu could not be displayed',
        message: 'The product menu hit an unexpected error. Retry the catalog.',
        actionLabel: 'Retry Catalog',
        onAction: () {
          posLog('Manual catalog retry after workspace build error: $error');
          context.read<CatalogProvider>().load();
        },
        danger: true,
      ),
    );
  }

  Widget _buildProductWorkspace(CatalogProvider catalog) {
    // The workspace is deliberately a normal Column/GridView subtree inside
    // the parent ListView. The grid is shrink-wrapped and never scrolls on
    // its own, so there is no nested viewport/flex dependency.
    if (catalog.isLoading && catalog.products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Popular Items',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 190,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (_, index) => const _ProductSkeletonCard(),
            ),
          ],
        ),
      );
    }

    if (catalog.errorMessage != null && catalog.products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: _PosStateMessage(
          icon: Icons.error_outline,
          title: 'Could not load products',
          message: catalog.errorMessage!,
          actionLabel: 'Try Again',
          onAction: catalog.load,
          danger: true,
        ),
      );
    }

    final products = _filteredProducts(catalog);
    if (products.isEmpty) {
      final filtered =
          _searchQuery.isNotEmpty || _selectedCategoryId != null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: _PosStateMessage(
          icon: filtered
              ? Icons.search_off_rounded
              : Icons.fastfood_outlined,
          title: filtered ? 'No matching products' : 'No products available',
          message: filtered
              ? 'Try another search or category.'
              : 'Refresh the catalog or check your backend product list.',
          actionLabel: 'Refresh Catalog',
          onAction: catalog.load,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Popular Items',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (catalog.isLoading) const LinearProgressIndicator(),
          if (catalog.isLoading) const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisExtent: 190,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final product = products[index];
              return _ProductCard(
                product: product,
                requireTable: _orderMode == 'dine_in' &&
                    context.read<CartProvider>().tableId == null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PosStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool danger;

  const _PosStateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 52,
              color: danger ? AppColors.danger : AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSkeletonCard extends StatelessWidget {
  const _ProductSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FractionallySizedBox(
            widthFactor: .72,
            child: Container(height: 13, color: AppColors.border),
          ),
          const SizedBox(height: 7),
          FractionallySizedBox(
            widthFactor: .38,
            child: Container(height: 11, color: AppColors.primaryLight),
          ),
        ],
      ),
    );
  }
}

class _ProductSkeletonGrid extends StatelessWidget {
  const _ProductSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 190,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 6,
      itemBuilder: (_, index) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FractionallySizedBox(
              widthFactor: .72,
              child: Container(height: 13, color: AppColors.border),
            ),
            const SizedBox(height: 7),
            FractionallySizedBox(
              widthFactor: .38,
              child: Container(height: 11, color: AppColors.primaryLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool requireTable;

  _ProductCard({
    required this.product,
    this.requireTable = false,
  });

  @override
  Widget build(BuildContext context) {
    final cart =
        context.watch<CartProvider>();

    final qtyInCart = cart.items
        .where(
          (i) => i.product.id == product.id,
        )
        .fold(
          0,
          (sum, item) =>
              sum + item.quantity,
        );

    final unavailable = !product.isAvailable;
    final outOfStock =
        product.trackInventory &&
            product.stock <= 0;

    return InkWell(
      onTap: (outOfStock || unavailable)
          ? null
          : () {
              if (requireTable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select a dining table first.')),
                );
                return;
              }
              context
                  .read<CartProvider>()
                  .addProduct(product);

              ScaffoldMessenger.of(
                context,
              )
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      '${product.name} added to cart',
                    ),
                    duration:
                        Duration(
                      milliseconds: 700,
                    ),
                  ),
                );
            },
      borderRadius:
          BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (outOfStock || unavailable)
              ? AppColors.background
              : AppColors.surface,
          borderRadius:
              BorderRadius.circular(14),
          border: Border.all(
            color: qtyInCart > 0
                ? AppColors.primary
                : AppColors.border,
            width:
                qtyInCart > 0 ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            ProductImage(
              name: product.name,
              imageUrl: product.imageUrl,
              width: double.infinity,
              height: 86,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(10),
            ),
            SizedBox(height: 8),

            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: qtyInCart > 0
                      ? Padding(
                          key: const ValueKey('qty'),
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                    padding:
                        EdgeInsets
                            .symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          AppColors.primary,
                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                    ),
                    child: Text(
                      '$qtyInCart',
                      style:
                          TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no-qty')),
                ),
              ],
            ),

            Spacer(),

            if (unavailable)
              Text(
                'Unavailable for sale',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      AppColors.danger,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              )
            else if (product.isLowStock)
              Text(
                '${product.stock} left',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    TextStyle(
                  color:
                      AppColors.warning,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

            SizedBox(height: 2),

            Text(
              Formatters.currency(
                product.sellingPrice,
              ),
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  TextStyle(
                color:
                    AppColors.primary,
                fontWeight:
                    FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}