import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import 'cart_sheet.dart';
import 'payment_sheet.dart';

/// Dedicated fresh flow for counter Takeaway and Delivery orders.
///
/// QR ordering is not used here and its existing implementation is untouched.
/// This screen deliberately avoids the old POS mode-switch/layout tree so a
/// Takeaway or Delivery order always gets a normal bounded product viewport.
class DirectOrderScreen extends StatefulWidget {
  final String orderType;

  const DirectOrderScreen({super.key, required this.orderType})
      : assert(orderType == 'takeaway' || orderType == 'delivery');

  bool get isDelivery => orderType == 'delivery';

  @override
  State<DirectOrderScreen> createState() => _DirectOrderScreenState();
}

class _DirectOrderScreenState extends State<DirectOrderScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Explicit fresh-start reset for every direct order.
      final cart = context.read<CartProvider>();
      cart.clear();
      cart.configureContext(orderType: widget.orderType);
      context.read<CatalogProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => mounted ? setState(() {}) : null;

  List<Product> _filteredProducts(CatalogProvider catalog) {
    var result = catalog.productsForCategory(_categoryId);
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((product) => product.name.toLowerCase().contains(query))
          .toList();
    }
    return result;
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
      builder: (_) => CartSheet(onContinueToPayment: _openPayment),
    );
  }

  void _openPayment() {
    if (!mounted) return;
    Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cart = context.watch<CartProvider>();
    final products = _filteredProducts(catalog);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.isDelivery ? 'Delivery Order' : 'Takeaway Order'),
            Text(
              widget.isDelivery
                  ? 'Create a new delivery order'
                  : 'Create a new counter order',
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final product = products[index];
        return _ProductRow(
          product: product,
          onAdd: () => context.read<CartProvider>().addProduct(product),
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

class _ProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;

  const _ProductRow({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final unavailable = !product.isAvailable ||
        (product.trackInventory && product.stock <= 0);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: unavailable ? null : onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ProductImage(
                name: product.name,
                imageUrl: product.imageUrl,
                width: 72,
                height: 72,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Formatters.currency(product.sellingPrice),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (unavailable) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.isAvailable ? 'Out of stock' : 'Unavailable',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                unavailable
                    ? Icons.block_outlined
                    : Icons.add_circle_rounded,
                color: unavailable ? AppColors.textMuted : AppColors.primary,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
