import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/cart_provider.dart';
import '../../models/cart_item.dart';

import 'customer_picker_sheet.dart';
import 'payment_sheet.dart';

class CartSheet extends StatefulWidget {
  CartSheet({super.key});

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
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
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
                  SizedBox(height: 10),

                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.fromLTRB(
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
                        Spacer(),

                        if (!cart.isEmpty)
                          TextButton(
                            onPressed: () => cart.clearItems(),
                            child: Text('Clear'),
                          ),

                        IconButton(
                          icon: Icon(Icons.close),
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
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            children: [
                              ...cart.items.map(
                                (item) => _CartLineTile(item: item),
                              ),

                              SizedBox(height: 16),

                              _buildCustomerSelector(
                                context,
                                cart,
                              ),

                              if (cart.orderType == 'delivery') ...[
                                SizedBox(height: 14),
                                _buildDeliverySection(
                                  context,
                                  cart,
                                ),
                              ],

                              SizedBox(height: 16),

                              _buildDiscountField(
                                context,
                                cart,
                              ),

                              SizedBox(height: 16),

                              _buildNotesField(
                                context,
                                cart,
                              ),

                              SizedBox(height: 120),
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
          builder: (_) => CustomerPickerSheet(),
        );

        if (customer != null) {
          cart.setCustomer(customer);
          _syncDeliveryAddress(cart);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(14),
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

            SizedBox(width: 10),

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
                icon: Icon(
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
      padding: EdgeInsets.all(14),
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
              SizedBox(width: 8),
              Text(
                'Delivery Details',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          SizedBox(height: 14),

          TextField(
            controller: _deliveryPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              hintText: 'Enter 10-digit phone number',
              prefixIcon: Icon(Icons.phone_outlined),
              counterText: '',
            ),
            onChanged: cart.setDeliveryPhone,
          ),

          SizedBox(height: 12),

          TextField(
            controller: _deliveryAddressController,
            keyboardType: TextInputType.streetAddress,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Delivery Address *',
              hintText: 'House no, street, area, city...',
              prefixIcon: Icon(Icons.location_on_outlined),
              alignLabelWithHint: true,
            ),
            onChanged: cart.setDeliveryAddress,
          ),

          if (cart.selectedCustomer?.address != null &&
              cart.selectedCustomer!.address!.trim().isNotEmpty) ...[
            SizedBox(height: 8),
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
    return TextField(
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
      ),
      decoration: InputDecoration(
        labelText: 'Discount (₹)',
        prefixIcon: Icon(Icons.percent),
      ),
      onChanged: (value) {
        cart.setDiscount(
          double.tryParse(value) ?? 0,
        );
      },
    );
  }

  Widget _buildNotesField(
    BuildContext context,
    CartProvider cart,
  ) {
    return TextField(
      decoration: InputDecoration(
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
      padding: EdgeInsets.fromLTRB(
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

            if (cart.discount > 0)
              _summaryRow(
                'Discount',
                '- ${Formatters.currency(cart.discount)}',
              ),

            Divider(height: 18),

            _summaryRow(
              'Grand Total',
              Formatters.currency(cart.grandTotal),
              bold: true,
            ),

            SizedBox(height: 14),

            ElevatedButton(
              onPressed: () {
                if (cart.orderType == 'delivery') {
                  final phone = cart.deliveryPhone.trim();
                  final address = cart.deliveryAddress.trim();

                  if (cart.selectedCustomer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please select a customer for delivery.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please enter a valid 10-digit phone number.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (address.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please enter the delivery address.',
                        ),
                      ),
                    );
                    return;
                  }
                }

                Navigator.pop(context);

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => PaymentSheet(),
                );
              },
              child: Text(
                cart.orderType == 'delivery'
                    ? 'CONTINUE TO PAYMENT'
                    : 'CREATE BILL',
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
      padding: EdgeInsets.symmetric(
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

  _CartLineTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  Formatters.currency(
                    item.product.sellingPrice,
                  ),
                  style:
                      Theme.of(context).textTheme.bodyMedium,
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
                EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${item.quantity}',
              style: TextStyle(
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

          SizedBox(width: 10),

          SizedBox(
            width: 64,
            child: Text(
              Formatters.currency(
                item.lineTotal,
              ),
              textAlign: TextAlign.right,
              style: TextStyle(
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
        padding: EdgeInsets.all(6),
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