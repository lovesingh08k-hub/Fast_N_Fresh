import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/cart_item.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import 'cart_sheet.dart';

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
    WidgetsBinding.instance.addObserver(this);
    _setScreenAwake(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final catalog = context.read<CatalogProvider>();

      if (catalog.products.isEmpty && !catalog.isLoading) {
        catalog.load();
      }

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

  List<Product> _filteredProducts(
    CatalogProvider catalog,
  ) {
    var products =
        catalog.productsForCategory(_selectedCategoryId);

    if (_searchQuery.isNotEmpty) {
      products = products.where((product) {
        return product.name
            .toLowerCase()
            .contains(_searchQuery);
      }).toList();
    }

    return products;
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tableName != null
              ? 'POS • ${widget.tableName}'
              : 'Point of Sale',
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Cart',
                onPressed: _openCart,
                icon: Icon(
                  Icons.shopping_cart_outlined,
                ),
              ),

              if (cart.itemCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${cart.itemCount}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          if (widget.tableId != null)
            _buildTableBanner(),

          _buildSearch(),

          _buildCategories(catalog),

          Expanded(
            child: _buildProducts(catalog),
          ),
        ],
      ),

      bottomNavigationBar: cart.itemCount > 0
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
        onChanged: (_) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search products...',
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
      return SizedBox(height: 4);
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

  Widget _buildProducts(
    CatalogProvider catalog,
  ) {
    if (catalog.isLoading &&
        catalog.products.isEmpty) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    if (catalog.errorMessage != null &&
        catalog.products.isEmpty) {
      return ListView(
        physics:
            AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(24),
        children: [
          SizedBox(height: 80),

          Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.danger,
          ),

          SizedBox(height: 16),

          Center(
            child: Text(
              'Could not load products',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),

          SizedBox(height: 8),

          Center(
            child: Text(
              catalog.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),

          SizedBox(height: 20),

          Center(
            child: ElevatedButton.icon(
              onPressed: catalog.load,
              icon: Icon(
                Icons.refresh,
              ),
              label: Text(
                'Try Again',
              ),
            ),
          ),
        ],
      );
    }

    final products =
        _filteredProducts(catalog);

    if (products.isEmpty) {
      return ListView(
        physics:
            AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(24),
        children: [
          SizedBox(height: 80),

          Icon(
            Icons.fastfood_outlined,
            size: 52,
            color: AppColors.textMuted,
          ),

          SizedBox(height: 16),

          Center(
            child: Text(
              'No products found',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),

          SizedBox(height: 8),

          Center(
            child: Text(
              'Try another search or category.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding:
              EdgeInsets.fromLTRB(
            16,
            8,
            16,
            20,
          ),
          gridDelegate:
              SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 190,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            return _ProductCard(
              product: products[index],
            );
          },
        ),

        if (catalog.isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;

  _ProductCard({
    required this.product,
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

    final outOfStock =
        product.trackInventory &&
            product.stock <= 0;

    return InkWell(
      onTap: outOfStock
          ? null
          : () {
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
      child: Container(
        padding:
            EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: outOfStock
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
            if (product.hasImage) ...[
              Container(
                height: 72,
                width: double.infinity,
                decoration:
                    BoxDecoration(
                  color:
                      AppColors.background,
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                clipBehavior:
                    Clip.antiAlias,
                child: Image.network(
                  ApiConfig
                      .resolveAssetUrl(
                    product.imageUrl,
                  ),
                  fit: BoxFit.contain,
                  // Decode at roughly the on-screen size (accounting for
                  // high-DPI screens) instead of full resolution — this tile
                  // is only ever shown at 72px tall.
                  cacheHeight: 72 * 3,
                  errorBuilder:
                      (_, __, ___) {
                    return Icon(
                      Icons
                          .fastfood_outlined,
                      size: 30,
                      color: AppColors
                          .textSecondary,
                    );
                  },
                ),
              ),

              SizedBox(height: 8),
            ],

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

                if (qtyInCart > 0) ...[
                  SizedBox(width: 6),

                  Container(
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
                ],
              ],
            ),

            Spacer(),

            if (outOfStock)
              Text(
                'Out of stock',
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