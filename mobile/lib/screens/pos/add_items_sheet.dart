import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';

/// Product picker that can be opened while reviewing a cart/payment.
///
/// It reuses the live catalog and existing CartProvider so adding another
/// item does not lose the current customer, discount, notes or dine-in
/// order context.
class AddItemsSheet extends StatefulWidget {
  const AddItemsSheet({super.key});

  @override
  State<AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSkeleton extends StatelessWidget {
  const _AddItemsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 185,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 6,
      itemBuilder: (_, __) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 130,
                height: 12,
                color: AppColors.border,
              ),
              const SizedBox(height: 7),
              Container(
                width: 55,
                height: 11,
                color: AppColors.primaryLight,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddItemsSheetState extends State<AddItemsSheet> {
  final TextEditingController _search = TextEditingController();

  String? _categoryId;

  // Guards the bottom "Save Order" button against a double tap while the
  // sheet is in the process of closing (the actual persistence happens in
  // the caller, e.g. TableDetailScreen, right after this sheet pops).
  bool _closing = false;

  void _saveOrder() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.pop(context, true);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final catalog = context.read<CatalogProvider>();
      catalog.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Product> _products(CatalogProvider catalog) {
    var items = catalog.productsForCategory(_categoryId);

    final query = _search.text.trim().toLowerCase();

    if (query.isNotEmpty) {
      items = items
          .where(
            (product) => product.name.toLowerCase().contains(query),
          )
          .toList();
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cart = context.watch<CartProvider>();

    return AnimatedBuilder(
      animation: AppColors.progress,
      builder: (context, _) {
        return _buildContent(
          context,
          catalog,
          cart,
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    CatalogProvider catalog,
    CartProvider cart,
  ) {
    final products = _products(catalog);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * .88,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Drag handle
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add Items',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${cart.itemCount} in cart',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),

            // Categories
            if (catalog.categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: catalog.categories.length + 1,
                  separatorBuilder: (_, __) {
                    return const SizedBox(width: 8);
                  },
                  itemBuilder: (_, index) {
                    // All category
                    if (index == 0) {
                      return ChoiceChip(
                        label: const Text('All'),
                        selected: _categoryId == null,
                        onSelected: (_) {
                          setState(() {
                            _categoryId = null;
                          });
                        },
                      );
                    }

                    final category = catalog.categories[index - 1];

                    return ChoiceChip(
                      label: Text(category.name),
                      selected: _categoryId == category.id,
                      onSelected: (_) {
                        setState(() {
                          _categoryId = category.id;
                        });
                      },
                    );
                  },
                ),
              ),

            // Products
            Expanded(
              child: catalog.isLoading && catalog.products.isEmpty
                  ? const _AddItemsSkeleton()
                  : catalog.errorMessage != null && catalog.products.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_off_outlined,
                                  size: 42,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  catalog.errorMessage!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: catalog.load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : products.isEmpty
                          ? Center(
                              child: Text(
                                'No items found',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                24,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 280,
                                mainAxisExtent: 185,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: products.length,
                              itemBuilder: (_, index) {
                                final product = products[index];

                                final qty = cart.items
                                    .where(
                                      (item) => item.product.id == product.id,
                                    )
                                    .fold<int>(
                                      0,
                                      (sum, item) => sum + item.quantity,
                                    );

                                final unavailable = !product.isAvailable;

                                final outOfStock = product.trackInventory &&
                                    product.stock <= 0;

                                final disabled = outOfStock || unavailable;

                                void addOne() {
                                  cart.addProduct(product);
                                }

                                return InkWell(
                                  onTap: disabled
                                      ? null
                                      : () {
                                          addOne();

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${product.name} added',
                                              ),
                                              duration: const Duration(
                                                milliseconds: 650,
                                              ),
                                            ),
                                          );
                                        },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: (outOfStock || unavailable)
                                          ? AppColors.background
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: qty > 0
                                            ? AppColors.primary
                                            : AppColors.border,
                                        width: qty > 0 ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Product image
                                        ProductImage(
                                          name: product.name,
                                          imageUrl: product.imageUrl,
                                          width: double.infinity,
                                          height: 82,
                                          fit: BoxFit.cover,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),

                                        const SizedBox(height: 7),

                                        // Product name
                                        Text(
                                          product.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),

                                        const Spacer(),

                                        // Availability status
                                        if (unavailable)
                                          Text(
                                            'Unavailable',
                                            style: TextStyle(
                                              color: AppColors.danger,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        else if (outOfStock)
                                          Text(
                                            'Out of stock',
                                            style: TextStyle(
                                              color: AppColors.danger,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),

                                        const SizedBox(height: 4),

                                        // Price + quantity stepper
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '₹${product.sellingPrice.toStringAsFixed(0)}',
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),

                                            // Explicit [-] qty [+] stepper so
                                            // quantities can be reduced
                                            // without re-opening the sheet.
                                            qty > 0
                                                ? Container(
                                                    decoration: BoxDecoration(
                                                      color: AppColors
                                                          .primaryLight,
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        InkWell(
                                                          onTap: () => cart
                                                              .decrementQuantity(
                                                                  product.id),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20),
                                                          child: const Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                    5),
                                                            child: Icon(
                                                                Icons.remove,
                                                                size: 16),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 20,
                                                          child: Text(
                                                            '$qty',
                                                            textAlign:
                                                                TextAlign
                                                                    .center,
                                                            style: TextStyle(
                                                              color: AppColors
                                                                  .primary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                          ),
                                                        ),
                                                        InkWell(
                                                          onTap: disabled
                                                              ? null
                                                              : addOne,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      20),
                                                          child: const Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                    5),
                                                            child: Icon(
                                                                Icons.add,
                                                                size: 16),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),

            // Bottom "Save Order" bar. Matches the checkout/cart summary
            // styling used elsewhere so items + total are always visible
            // while picking food, with a single clear call to action.
            _buildSaveOrderBar(context, cart),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveOrderBar(BuildContext context, CartProvider cart) {
    final hasItems = cart.itemCount > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${cart.itemCount} ${cart.itemCount == 1 ? 'Item' : 'Items'}',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Formatters.currency(cart.subtotal),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: !hasItems || _closing ? null : _saveOrder,
                icon: _closing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('SAVE ORDER'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
