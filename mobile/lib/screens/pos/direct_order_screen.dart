import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/product_sizes.dart';
import '../../core/widgets/fresh_ui.dart';
import '../../core/widgets/pos_ui.dart';
import '../../core/widgets/product_image.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import 'cart_sheet.dart';
import 'payment_sheet.dart';
import 'running_orders_bar.dart';

/// Menu + cart for one Takeaway or Delivery counter (T1, D2...), opened
/// from the counters screen like a dine-in table. A free counter starts a
/// new order; a busy one ([resumeOrderId]) carries on with its order.
///
/// QR ordering is not used here and its existing implementation is untouched.
/// This screen deliberately avoids the old POS mode-switch/layout tree so a
/// Takeaway or Delivery order always gets a normal bounded product viewport.
class DirectOrderScreen extends StatefulWidget {
  final String orderType;

  /// Counter tag for a new order, e.g. "T1" or "D2".
  final String? slot;

  /// Open (unbilled) order to load and carry on with.
  final String? resumeOrderId;

  /// Opens the cart for billing as soon as the order is loaded, e.g. for a
  /// pending bill tapped in Bill History.
  final bool autoOpenCart;

  const DirectOrderScreen({
    super.key,
    required this.orderType,
    this.slot,
    this.resumeOrderId,
    this.autoOpenCart = false,
  }) : assert(orderType == 'takeaway' || orderType == 'delivery');

  bool get isDelivery => orderType == 'delivery';

  @override
  State<DirectOrderScreen> createState() => _DirectOrderScreenState();
}

class _DirectOrderScreenState extends State<DirectOrderScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _categoryId;
  bool _loadingOrder = false;

  /// The cart as last saved/loaded, to tell whether leaving loses changes.
  String _savedSnapshot = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadingOrder = widget.resumeOrderId != null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Explicit fresh-start reset for every direct order.
      final cart = context.read<CartProvider>();
      cart.clear();
      cart.configureContext(orderType: widget.orderType, tableCustomerLabel: widget.slot);
      context.read<CatalogProvider>().ensureLoaded();
      _savedSnapshot = _snapshot(cart);

      final resumeId = widget.resumeOrderId;
      if (resumeId != null) await _resume(resumeId);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => mounted ? setState(() {}) : null;

  Future<void> _resume(String orderId) async {
    final cart = context.read<CartProvider>();
    String? error;
    try {
      await loadOpenOrderIntoCart(cart, orderId);
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not open that order. Please try again.';
    }
    if (!mounted) return;
    setState(() => _loadingOrder = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      cart.clear();
      Navigator.of(context).pop();
      return;
    }
    _savedSnapshot = _snapshot(cart);
    if (widget.autoOpenCart) await _openCart();
  }

  String _snapshot(CartProvider cart) {
    final items = cart.items.map((i) => '${i.product.id}x${i.quantity}').toList()..sort();
    return [
      items.join(','),
      cart.discount,
      cart.notes,
      cart.customerNameInput.trim(),
      cart.selectedCustomer?.id,
      cart.deliveryAddress,
      cart.deliveryPhone,
    ].join('|');
  }

  /// Leaving would lose items or edits that are not saved on the server.
  bool _hasUnsavedChanges(CartProvider cart) =>
      !_loadingOrder && !(cart.isEmpty && cart.openOrderId == null) && _snapshot(cart) != _savedSnapshot;

  List<Product> _filteredProducts(CatalogProvider catalog) {
    var result = catalog.productsForCategory(_categoryId);
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((product) => product.name.toLowerCase().contains(query))
          .toList();
    }
    return ProductSizes.collapse(result);
  }

  Future<void> _openCart() async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item first.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CartSheet(
        onContinueToPayment: _openPayment,
        onSaveAndSendToKitchen: _saveAndClose,
      ),
    );
  }

  /// "SAVE ORDER": keeps this counter's order open (unbilled) on the server
  /// and goes back to the counters, like sending a dine-in table's order.
  Future<void> _saveAndClose() async {
    if (!mounted) return;
    if (!await saveCartWithFeedback(context) || !mounted) return;
    context.read<CartProvider>().clear();
    Navigator.of(context).pop();
  }

  // The cart sheet closes itself before calling this, so this screen stays
  // under the payment sheet (closing the payment sheet returns to the menu).
  void _openPayment() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PaymentSheet(),
      );
    });
  }

  /// Back with unsaved items or edits: offer to keep them instead of
  /// silently losing them.
  Future<void> _onBackPressed() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this order?'),
        content: const Text(
          'Save it on this counter to bill it later, or discard the changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'save' && !await saveCartWithFeedback(context)) return;
    if (!mounted) return;
    context.read<CartProvider>().clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return PopScope(
      canPop: !_hasUnsavedChanges(cart),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cart = context.watch<CartProvider>();
    final products = _filteredProducts(catalog);
    final counter = cart.hasSlot ? cart.tableCustomerLabel : widget.slot;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.isDelivery ? 'Delivery' : 'Takeaway'}${counter == null ? '' : ' · $counter'}',
            ),
            Text(
              _loadingOrder
                  ? 'Loading order...'
                  : cart.openOrderId == null
                      ? 'New order'
                      : 'Running order',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: cart.isEmpty ? null : _openCart,
            icon: Badge(
              isLabelVisible: cart.itemCount > 0,
              label: Text('${cart.itemCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingOrder) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search menu items',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
          ),
          _buildCategories(catalog),
          Expanded(child: _buildProducts(catalog, products)),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _openCart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_cart_checkout_rounded),
                    const SizedBox(width: 10),
                    Text(
                      'Review & Pay  •  ${Formatters.currency(cart.grandTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategories(CatalogProvider catalog) {
    if (catalog.categories.isEmpty) return const SizedBox(height: 4);

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: catalog.categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final all = index == 0;
          final category = all ? null : catalog.categories[index - 1];
          final selected = all
              ? _categoryId == null
              : _categoryId == category!.id;
          return ChoiceChip(
            selected: selected,
            label: Text(all ? 'All' : category!.name),
            onSelected: (_) => setState(() {
              _categoryId = all ? null : category!.id;
            }),
          );
        },
      ),
    );
  }

  Widget _buildProducts(CatalogProvider catalog, List<Product> products) {
    if (catalog.isLoading && catalog.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (catalog.errorMessage != null && catalog.products.isEmpty) {
      return _stateMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Menu could not be loaded',
        message: catalog.errorMessage!,
        action: catalog.load,
      );
    }

    if (products.isEmpty) {
      return _stateMessage(
        icon: Icons.fastfood_outlined,
        title: _searchController.text.trim().isEmpty
            ? 'No products available'
            : 'No matching items',
        message: _searchController.text.trim().isEmpty
            ? 'Check the product catalog and try again.'
            : 'Try another item name or category.',
        action: catalog.load,
      );
    }

    // Read during build; the item builder below runs later, during layout.
    final cart = context.watch<CartProvider>();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final product = products[index];
        final ids = ProductSizes.variantIds(product, catalog.products);
        final inCart = cart.items.where((i) => ids.contains(i.product.id)).toList();
        final quantity = inCart.fold<int>(0, (n, i) => n + i.quantity);
        return _ProductRow(
          product: product,
          priceLabel: ProductSizes.priceLabel(product, catalog.products),
          quantity: quantity,
          onAdd: () async {
            final chosen =
                await ProductSizes.pick(context, product, catalog.products);
            if (chosen == null || !mounted) return;
            context.read<CartProvider>().addProduct(chosen);
          },
          // With sizes, "−" removes from the last size added.
          onRemove: inCart.isEmpty
              ? null
              : () => context.read<CartProvider>().decrementQuantity(inCart.last.product.id),
        );
      },
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String message,
    required Future<void> Function() action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: action, child: const Text('Refresh menu')),
          ],
        ),
      ),
    );
  }
}

/// Menu item card: photo (or dish tile), veg/non-veg mark, name,
/// description, price and a −/+ quantity control.
class _ProductRow extends StatelessWidget {
  final Product product;
  final String priceLabel;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;

  const _ProductRow({
    required this.product,
    required this.priceLabel,
    required this.quantity,
    required this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final unavailable = !product.isAvailable ||
        (product.trackInventory && product.stock <= 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: unavailable ? null : onAdd,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: FreshUi.card(
            radius: 20,
            tint: quantity > 0 ? AppColors.primary : null,
            tintStrength: quantity > 0 ? .04 : 0,
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Opacity(
                    opacity: unavailable ? .45 : 1,
                    child: ProductImage(
                      name: product.name,
                      imageUrl: product.imageUrl,
                      width: 84,
                      height: 84,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  if (product.foodType.isNotEmpty)
                    Positioned(left: 6, top: 6, child: FoodTypeMark(foodType: product.foodType)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductSizes.baseName(product),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary),
                    ),
                    if (product.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceLabel,
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        if (unavailable)
                          StatusPill(
                            label: product.isAvailable ? 'Out of stock' : 'Unavailable',
                            color: AppColors.danger,
                          )
                        else
                          QtyStepper(quantity: quantity, onAdd: onAdd, onRemove: onRemove),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
