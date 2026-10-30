import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/cart_provider.dart';
import '../../models/cart_item.dart';
import '../../core/widgets/product_image.dart';

import 'customer_picker_sheet.dart';
import 'add_items_sheet.dart';

class CartSheet extends StatefulWidget {
  final VoidCallback? onContinueToPayment;
  final VoidCallback? onSaveAndSendToKitchen;

  const CartSheet({super.key, this.onContinueToPayment, this.onSaveAndSendToKitchen});

  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  late final TextEditingController _deliveryAddressController;
  late final TextEditingController _deliveryPhoneController;

  @override
  void initState() {
    super.initState();

    final cart = context.read<CartProvider>();

    _deliveryAddressController = TextEditingController(
      text: cart.deliveryAddress,
    );

    _deliveryPhoneController = TextEditingController(
      text: cart.deliveryPhone,
    );
  }

  @override
  void dispose() {
    _deliveryAddressController.dispose();
    _deliveryPhoneController.dispose();
    super.dispose();
  }

  void _syncDeliveryAddress(CartProvider cart) {
    if (_deliveryAddressController.text != cart.deliveryAddress) {
      _deliveryAddressController.text = cart.deliveryAddress;
      _deliveryAddressController.selection = TextSelection.fromPosition(
        TextPosition(offset: _deliveryAddressController.text.length),
      );
    }

    if (_deliveryPhoneController.text != cart.deliveryPhone) {
      _deliveryPhoneController.text = cart.deliveryPhone;
      _deliveryPhoneController.selection = TextSelection.fromPosition(
        TextPosition(offset: _deliveryPhoneController.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        // This sheet is pushed via showModalBottomSheet on top of POS and is
        // built from the legacy AppColors palette (background/border/etc.).
        // A freshly-opened modal only paints once with whatever
        // AppColors.progress happens to be at that instant; without this it
        // can freeze mid theme-transition showing a washed-out blend where
        // the sheet background and its cards read as the same color.
        // Wrapping in AnimatedBuilder keeps it repainting in sync with the
        // palette for as long as the sheet is open.
        return AnimatedBuilder(
          animation: AppColors.progress,
          builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(26),
            ),
          ),
          child: Consumer<CartProvider>(
            builder: (context, cart, _) {
              // Keep UI synchronized if customer selection fills
              // saved delivery details.
              if (cart.orderType == 'delivery') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _syncDeliveryAddress(cart);
                });
              }

              return Column(
                children: [
                  const SizedBox(height: 10),

                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      14,
                      12,
                      8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Current Cart',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),

                        if (!cart.isEmpty) ...[
                          TextButton.icon(
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const AddItemsSheet(),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Items'),
                          ),
                          TextButton(
                            onPressed: () => cart.clearItems(),
                            child: const Text('Clear'),
                          ),
                        ],

                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: cart.isEmpty
                        ? Center(
                            child: Text(
                              'Your cart is empty',
                              style: TextStyle(
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            children: [
                              ...cart.items.map(
                                (item) => _CartLineTile(item: item),
                              ),

                              const SizedBox(height: 16),

                              _buildCustomerSelector(
                                context,
                                cart,
                              ),

                              if (cart.selectedCustomer == null) ...[
                                const SizedBox(height: 10),
                                _buildCustomerNameField(cart),
                              ],

                              if (cart.orderType == 'delivery') ...[
                                const SizedBox(height: 14),
                                _buildDeliverySection(
                                  context,
                                  cart,
                                ),
                              ],

                              const SizedBox(height: 16),

                              _buildDiscountField(
                                context,
                                cart,
                              ),

                              const SizedBox(height: 16),

                              _buildNotesField(
                                context,
                                cart,
                              ),

                              const SizedBox(height: 120),
                            ],
                          ),
                  ),

                  if (!cart.isEmpty)
                    _buildSummaryAndCheckout(
                      context,
                      cart,
                    ),
                ],
              );
            },
          ),
          ),
        );
      },
    );
  }

  Widget _buildCustomerSelector(
    BuildContext context,
    CartProvider cart,
  ) {
    return InkWell(
      onTap: () async {
        final customer = await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const CustomerPickerSheet(),
        );

        if (customer != null) {
          cart.setCustomer(customer);
          _syncDeliveryAddress(cart);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_outline,
              size: 20,
              color: AppColors.textSecondary,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                cart.selectedCustomer?.name ??
                    (cart.orderType == 'delivery'
                        ? 'Select customer (required for delivery)'
                        : 'Select customer (optional)'),
                style: TextStyle(
                  color: cart.selectedCustomer != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            if (cart.selectedCustomer != null)
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                ),
                onPressed: () {
                  cart.setCustomer(null);

                  if (cart.orderType == 'delivery') {
                    _deliveryAddressController.clear();
                    _deliveryPhoneController.clear();

                    cart.setDeliveryAddress('');
                    cart.setDeliveryPhone('');
                  }
                },
              )
            else
              Icon(
                Icons.chevron_right,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliverySection(
    BuildContext context,
    CartProvider cart,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.delivery_dining_outlined,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Delivery Details',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          TextField(
            controller: _deliveryPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              hintText: 'Enter 10-digit phone number',
              prefixIcon: Icon(Icons.phone_outlined),
              counterText: '',
            ),
            onChanged: cart.setDeliveryPhone,
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _deliveryAddressController,
            keyboardType: TextInputType.streetAddress,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Delivery Address *',
              hintText: 'House no, street, area, city...',
              prefixIcon: Icon(Icons.location_on_outlined),
              alignLabelWithHint: true,
            ),
            onChanged: cart.setDeliveryAddress,
          ),

          if (cart.selectedCustomer?.address != null &&
              cart.selectedCustomer!.address!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Customer saved address is loaded automatically. You can edit it for this order.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountField(
    BuildContext context,
    CartProvider cart,
  ) {
    final percent = cart.discountType == 'percent';
    final quote = cart.quoteIsCurrent ? cart.quote : null;
    final hasDiscount = percent ? cart.discountPercent > 0 : cart.discount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                // Rebuild the field when switching ₹ / % so it shows that value.
                key: ValueKey('discount-${cart.discountType}'),
                initialValue: hasDiscount
                    ? (percent ? cart.discountPercent : cart.discount).toStringAsFixed(0)
                    : '',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: percent ? 'Discount (%)' : 'Discount (₹)',
                  prefixIcon: const Icon(Icons.discount_outlined),
                ),
                onChanged: (value) {
                  final amount = double.tryParse(value) ?? 0;
                  if (percent) {
                    cart.setPercentDiscount(amount);
                  } else {
                    cart.setDiscount(amount);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'flat', label: Text('₹')),
                ButtonSegment(value: 'percent', label: Text('%')),
              ],
              selected: {cart.discountType},
              onSelectionChanged: (value) {
                if (value.first == 'percent') {
                  cart.setPercentDiscount(0);
                } else {
                  cart.setDiscount(0);
                }
              },
            ),
          ],
        ),
        if (hasDiscount) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: cart.discountReason,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Discount reason (optional)',
              hintText: 'e.g. Regular customer, Staff, Festival offer',
              counterText: '',
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
            onChanged: cart.setDiscountReason,
          ),
        ],
        if ((quote?.serviceChargePercent ?? 0) > 0 || cart.serviceChargeOn != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Service charge'),
            subtitle: Text(
              quote != null && quote.serviceCharge > 0
                  ? '${quote.serviceChargePercent.toStringAsFixed(0)}% · ${Formatters.currency(quote.serviceCharge)}'
                  : 'Not added on this bill',
            ),
            value: cart.serviceChargeOn ?? (quote?.serviceCharge ?? 0) > 0,
            onChanged: (value) => cart.setServiceCharge(value),
          ),
      ],
    );
  }

  /// Optional name printed on the bill/KOT instead of "Customer 1", for
  /// customers who are not saved in the customer list.
  Widget _buildCustomerNameField(CartProvider cart) {
    final autoLabel = cart.tableCustomerLabel;
    return TextFormField(
      initialValue: cart.customerNameInput,
      textCapitalization: TextCapitalization.words,
      maxLength: 60,
      decoration: InputDecoration(
        labelText: 'Customer name (optional)',
        hintText: autoLabel ?? 'Printed on the bill',
        counterText: '',
        prefixIcon: const Icon(Icons.badge_outlined),
      ),
      onChanged: cart.setCustomerNameInput,
    );
  }

  Widget _buildNotesField(
    BuildContext context,
    CartProvider cart,
  ) {
    return TextField(
      decoration: const InputDecoration(
        labelText: 'Order notes (optional)',
        prefixIcon: Icon(Icons.note_outlined),
      ),
      onChanged: cart.setNotes,
    );
  }

  Widget _buildSummaryAndCheckout(
    BuildContext context,
    CartProvider cart,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryRow(
              'Subtotal',
              Formatters.currency(cart.subtotal),
            ),

            if (cart.quoteIsCurrent)
              for (final row in cart.quote!.rows())
                _summaryRow(
                  row.$1,
                  row.$2 < 0 ? '- ${Formatters.currency(-row.$2)}' : Formatters.currency(row.$2),
                )
            else if (cart.discount > 0)
              _summaryRow(
                'Discount',
                '- ${Formatters.currency(cart.discount)}',
              ),

            const Divider(height: 18),

            _summaryRow(
              'Grand Total',
              Formatters.currency(cart.grandTotal),
              bold: true,
            ),

            const SizedBox(height: 14),

            // Resumed takeaway/delivery orders can be re-saved after edits;
            // dine-in tabs keep their own save flow on the table screen.
            if ((cart.openOrderId == null || cart.orderType != 'dine_in') &&
                widget.onSaveAndSendToKitchen != null) ...[
              OutlinedButton.icon(
                onPressed: () {
                  if (cart.orderType == 'delivery') {
                    final phone = cart.deliveryPhone.trim();
                    final address = cart.deliveryAddress.trim();
                    if (cart.selectedCustomer == null || !RegExp(r'^\d{10}$').hasMatch(phone) || address.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Complete customer, phone and delivery address first.')),
                      );
                      return;
                    }
                  }
                  Navigator.of(context).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onSaveAndSendToKitchen?.call();
                  });
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('SAVE ORDER'),
              ),
              const SizedBox(height: 8),
            ],

            ElevatedButton(
              onPressed: () {
                if (cart.orderType == 'delivery') {
                  final phone = cart.deliveryPhone.trim();
                  final address = cart.deliveryAddress.trim();

                  if (cart.selectedCustomer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please select a customer for delivery.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter a valid 10-digit phone number.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (address.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter the delivery address.',
                        ),
                      ),
                    );
                    return;
                  }
                }

                // Close this sheet first. Opening another modal from the
                // deactivated sheet context can trigger Flutter's
                // InheritedElement `_dependents.isEmpty` assertion. The
                // parent POS screen owns the safe payment navigation.
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onContinueToPayment?.call();
                });
              },
              child: const Text(
                'CONTINUE TO PAYMENT',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight:
                  bold ? FontWeight.w700 : FontWeight.w500,
              color: bold
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 18 : 14,
              fontWeight:
                  bold ? FontWeight.w800 : FontWeight.w600,
              color: bold
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final CartItem item;

  const _CartLineTile({
    required this.item,
  });

  Future<void> _editNote(BuildContext context, CartProvider cart) async {
    final controller = TextEditingController(text: item.note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.product.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Note for kitchen',
            hintText: 'e.g. Less spicy, no onion',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (note != null) cart.setItemNote(item.product.id, note);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        children: [
          ProductImage(
            name: item.product.name,
            imageUrl: item.product.imageUrl,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Formatters.currency(
                    item.product.sellingPrice,
                  ),
                  style:
                      Theme.of(context).textTheme.bodyMedium,
                ),
                InkWell(
                  onTap: () => _editNote(context, cart),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.note.isEmpty ? '+ Add note for kitchen' : 'Note: ${item.note}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.note.isEmpty ? AppColors.primary : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          _qtyButton(
            Icons.remove,
            () => cart.decrementQuantity(
              item.product.id,
            ),
          ),

          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${item.quantity}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),

          _qtyButton(
            Icons.add,
            () => cart.incrementQuantity(
              item.product.id,
            ),
          ),

          const SizedBox(width: 10),

          SizedBox(
            width: 64,
            child: Text(
              Formatters.currency(
                item.lineTotal,
              ),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
        ),
      ),
    );
  }
}