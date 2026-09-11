import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../models/order.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';
import '../../services/misc_services.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/order_service.dart';

import 'bill_success_screen.dart';
import '../settings/printer_choice_sheet.dart';
import 'add_items_sheet.dart';
import '../../core/widgets/order_flow_stepper.dart';

enum _PaymentMethod {
  cash,
  upi,
  credit,
  mixed,
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({super.key});

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  _PaymentMethod _method = _PaymentMethod.cash;

  final TextEditingController _amountReceivedController =
      TextEditingController();

  final TextEditingController _upiRefController =
      TextEditingController();

  final TextEditingController _mixedCashController =
      TextEditingController();

  final TextEditingController _mixedUpiController =
      TextEditingController();

  final TextEditingController _mixedCreditController =
      TextEditingController();

  bool _submitting = false;
  String? _error;
  bool _taxEnabled = false;
  double _taxPercent = 0;
  int _splitCount = 1;

  @override
  void initState() {
    super.initState();
    _loadCheckoutSettings();
  }

  Future<void> _loadCheckoutSettings() async {
    try {
      final settings = await SettingsService().get();
      if (!mounted) return;
      setState(() {
        _taxEnabled = settings.taxEnabled;
        _taxPercent = settings.taxPercent;
      });
    } catch (_) {
      // Checkout still works if settings cannot be loaded.
    }
  }

  // Generated once when this payment sheet is opened, and reused unchanged
  // for every submit attempt of this bill (including a manual retry after a
  // failed/timed-out request). Lets the backend recognize a retry of the
  // same bill and avoid creating a duplicate paid order — see
  // OrderService.createOrder and orderController.js.
  final String _clientRequestId = Uuid().v4();

  @override
  void dispose() {
    _amountReceivedController.dispose();
    _upiRefController.dispose();
    _mixedCashController.dispose();
    _mixedUpiController.dispose();
    _mixedCreditController.dispose();

    super.dispose();
  }

  double get _change {
    final received =
        double.tryParse(
              _amountReceivedController.text.trim(),
            ) ??
            0;

    final cart = context.read<CartProvider>();

    final change = received - cart.grandTotal;

    return change > 0 ? change : 0;
  }

  double get _mixedCash {
    return double.tryParse(
          _mixedCashController.text.trim(),
        ) ??
        0;
  }

  double get _mixedUpi {
    return double.tryParse(
          _mixedUpiController.text.trim(),
        ) ??
        0;
  }

  double get _mixedCredit {
    return double.tryParse(
          _mixedCreditController.text.trim(),
        ) ??
        0;
  }

  double get _mixedTotal {
    return _mixedCash + _mixedUpi + _mixedCredit;
  }

  Future<void> _createBill() async {
    if (_submitting) return;

    final cart = context.read<CartProvider>();
    final total = cart.grandTotal;

    if (cart.isEmpty) {
      setState(() {
        _error = 'Cart is empty. Add at least one item.';
      });
      return;
    }

    if (total <= 0) {
      setState(() {
        _error = 'Bill total must be greater than zero.';
      });
      return;
    }

    // --------------------------------------------------
    // DELIVERY VALIDATION
    // --------------------------------------------------
    if (cart.orderType == 'delivery') {
      if (cart.selectedCustomer == null) {
        setState(() {
          _error =
              'Please select a customer for this delivery order.';
        });
        return;
      }

      final phone = cart.deliveryPhone.trim();

      if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
        setState(() {
          _error =
              'Please enter a valid 10-digit delivery phone number.';
        });
        return;
      }

      if (cart.deliveryAddress.trim().isEmpty) {
        setState(() {
          _error = 'Please enter the delivery address.';
        });
        return;
      }
    }

    // --------------------------------------------------
    // CREDIT VALIDATION
    // --------------------------------------------------
    if (_method == _PaymentMethod.credit &&
        cart.selectedCustomer == null) {
      setState(() {
        _error =
            'Please select a customer for UDHAR / Credit payment.';
      });
      return;
    }

    if (_method == _PaymentMethod.mixed &&
        _mixedCredit > 0 &&
        cart.selectedCustomer == null) {
      setState(() {
        _error =
            'Please select a customer when using Credit in Mixed payment.';
      });
      return;
    }

    // --------------------------------------------------
    // CASH VALIDATION
    // --------------------------------------------------
    if (_method == _PaymentMethod.cash) {
      final text = _amountReceivedController.text.trim();

      if (text.isNotEmpty) {
        final received = double.tryParse(text);

        if (received == null || received < 0) {
          setState(() {
            _error =
                'Please enter a valid amount received.';
          });
          return;
        }

        if (received < total) {
          setState(() {
            _error =
                'Amount received cannot be less than ${Formatters.currency(total)}.';
          });
          return;
        }
      }
    }

    // --------------------------------------------------
    // UPI VALIDATION
    // --------------------------------------------------
    // --------------------------------------------------
    // MIXED PAYMENT VALIDATION
    // --------------------------------------------------
    if (_method == _PaymentMethod.mixed) {
      if (_mixedCash < 0 ||
          _mixedUpi < 0 ||
          _mixedCredit < 0) {
        setState(() {
          _error =
              'Payment amounts cannot be negative.';
        });
        return;
      }

      if (_mixedTotal <= 0) {
        setState(() {
          _error =
              'Please enter the Mixed payment amounts.';
        });
        return;
      }

      final difference =
          (_mixedTotal - total).abs();

      if (difference > 0.01) {
        setState(() {
          _error =
              'Mixed payment must exactly equal ${Formatters.currency(total)}.';
        });
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    String paymentMethod;

    double? amountReceived;
    String? upiReference;

    double? cashPortion;
    double? upiPortion;
    double? creditPortion;

    switch (_method) {
      case _PaymentMethod.cash:
        paymentMethod = 'CASH';

        final text =
            _amountReceivedController.text.trim();

        if (text.isNotEmpty) {
          amountReceived =
              double.tryParse(text);
        }

        break;

      case _PaymentMethod.upi:
        paymentMethod = 'UPI';

        final reference =
            _upiRefController.text.trim();

        if (reference.isNotEmpty) {
          upiReference = reference;
        }

        break;

      case _PaymentMethod.credit:
        paymentMethod = 'CREDIT';
        break;

      case _PaymentMethod.mixed:
        paymentMethod = 'MIXED';

        cashPortion = _mixedCash;
        upiPortion = _mixedUpi;
        creditPortion = _mixedCredit;

        break;
    }

    try {
      final Order order;

      // ==================================================
      // EXISTING OPEN DINE-IN ORDER
      // ==================================================
      if (cart.openOrderId != null) {
        await OrderService().updateOpenOrderItems(
          cart.openOrderId!,
          items: cart.items,
          discount: cart.discount,
          notes: cart.notes,
          customerId: cart.selectedCustomer?.id,
        );

        order = await OrderService().checkoutOrder(
          cart.openOrderId!,
          paymentMethod: paymentMethod,
          amountReceived: amountReceived,
          upiReference: upiReference,
          customerId: cart.selectedCustomer?.id,
          cashPortion: cashPortion,
          upiPortion: upiPortion,
          creditPortion: creditPortion,
          discount: cart.discount,
        );
      }

      // ==================================================
      // NORMAL ORDER
      // ==================================================
      else {
        order = await OrderService().createOrder(
          items: cart.items,
          discount: cart.discount,
          paymentMethod: paymentMethod,
          amountReceived: amountReceived,
          upiReference: upiReference,
          customerId: cart.selectedCustomer?.id,
          notes: cart.notes,
          cashPortion: cashPortion,
          upiPortion: upiPortion,
          creditPortion: creditPortion,
          orderType: cart.orderType,
          tableId: cart.tableId,
          tableCustomerLabel:
              cart.tableCustomerLabel,

          // Delivery information.
          deliveryInfo:
              cart.orderType == 'delivery'
                  ? {
                      'address':
                          cart.deliveryAddress.trim(),
                      'phone':
                          cart.deliveryPhone.trim(),
                    }
                  : null,

          clientRequestId: _clientRequestId,
        );
      }

      if (!mounted) return;

      // ==================================================
      // SUCCESS
      // ==================================================

      // Clear the complete cart/order context.
      cart.clear();

      // Refresh product stock.
      await context
          .read<CatalogProvider>()
          .load();

      if (!mounted) return;

      // Close PaymentSheet.
      Navigator.of(context).pop();

      // Close contextual POS screen.
      Navigator.of(context).pop();

      // Show receipt.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BillSuccessScreen(
            order: order,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not create the bill. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // This sheet is pushed via showModalBottomSheet on top of POS and is
    // built from the legacy AppColors palette (background, etc.). A
    // freshly-opened modal only paints once with whatever AppColors.progress
    // happens to be at that instant, so without this it can freeze
    // mid theme-transition showing a washed-out light/dark blend. Wrapping
    // in AnimatedBuilder keeps it repainting in sync with the palette for
    // as long as the sheet is open.
    return AnimatedBuilder(
      animation: AppColors.progress,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cart = context.watch<CartProvider>();

    final needsCustomer =
        _method == _PaymentMethod.credit ||
        (_method == _PaymentMethod.mixed &&
            _mixedCredit > 0);

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              _checkoutHeader(cart),
              _checkoutSummary(cart),
              if (cart.orderType == 'dine_in')
                const OrderFlowStepper(currentStep: 4),
              Row(
                children: [
                  const Expanded(child: Text('Payment method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const AddItemsSheet(),
                    ),
                    icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                    label: const Text('Add items'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // --------------------------------------------------
              // HANDLE
              // --------------------------------------------------
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius:
                        BorderRadius.circular(4),
                  ),
                ),
              ),

              SizedBox(height: 16),

              // --------------------------------------------------
              // TITLE
              // --------------------------------------------------
              Text(
                cart.orderType == 'delivery'
                    ? 'Delivery Payment'
                    : 'Payment',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleLarge,
              ),

              SizedBox(height: 4),

              Text(
                'Grand Total: ${Formatters.currency(cart.grandTotal)}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),

              // --------------------------------------------------
              // DELIVERY SUMMARY
              // --------------------------------------------------
              if (cart.orderType == 'delivery') ...[
                SizedBox(height: 12),

                Container(
                  padding:
                      EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deliver To',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),

                      SizedBox(height: 6),

                      Text(
                        cart.selectedCustomer
                                ?.name ??
                            'Customer',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),

                      SizedBox(height: 4),

                      Text(
                        cart.deliveryPhone,
                        style: TextStyle(
                          color:
                              AppColors.textSecondary,
                        ),
                      ),

                      SizedBox(height: 4),

                      Text(
                        cart.deliveryAddress,
                        style: TextStyle(
                          color:
                              AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 18),

              // --------------------------------------------------
              // PAYMENT METHODS
              // --------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: _methodButton(
                      'CASH',
                      Icons.payments_outlined,
                      AppColors.cash,
                      _PaymentMethod.cash,
                    ),
                  ),

                  SizedBox(width: 8),

                  Expanded(
                    child: _methodButton(
                      'UPI',
                      Icons.qr_code_scanner,
                      AppColors.upi,
                      _PaymentMethod.upi,
                    ),
                  ),

                  SizedBox(width: 8),

                  Expanded(
                    child: _methodButton(
                      'CREDIT',
                      Icons
                          .account_balance_wallet_outlined,
                      AppColors.credit,
                      _PaymentMethod.credit,
                    ),
                  ),

                  SizedBox(width: 8),

                  Expanded(
                    child: _methodButton(
                      'MIXED',
                      Icons.call_split_outlined,
                      AppColors.primary,
                      _PaymentMethod.mixed,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 18),

              // --------------------------------------------------
              // CASH
              // --------------------------------------------------
              if (_method == _PaymentMethod.cash) ...[
                TextField(
                  controller:
                      _amountReceivedController,
                  keyboardType:
                      TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration:
                      InputDecoration(
                    labelText:
                        'Amount Received (optional)',
                    prefixIcon:
                        Icon(Icons.money),
                  ),
                  onChanged: (_) {
                    setState(() {
                      _error = null;
                    });
                  },
                ),

                if (_amountReceivedController
                    .text
                    .trim()
                    .isNotEmpty) ...[
                  SizedBox(height: 10),

                  Text(
                    'Change to return: ${Formatters.currency(_change)}',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],
              ],

              // --------------------------------------------------
              // UPI
              // --------------------------------------------------
              if (_method == _PaymentMethod.upi || (_method == _PaymentMethod.mixed && _mixedUpi > 0))
                TextField(
                  controller:
                      _upiRefController,
                  keyboardType:
                      TextInputType.text,
                  decoration:
                      InputDecoration(
                    labelText:
                        'UPI Reference / UTR (optional)',
                    prefixIcon:
                        Icon(Icons.tag),
                  ),
                  onChanged: (_) {
                    if (_error != null) {
                      setState(() {
                        _error = null;
                      });
                    }
                  },
                ),

              // --------------------------------------------------
              // CREDIT
              // --------------------------------------------------
              if (_method == _PaymentMethod.credit)
                _buildCreditSummary(cart),

              // --------------------------------------------------
              // MIXED
              // --------------------------------------------------
              if (_method == _PaymentMethod.mixed)
                _buildMixedPayment(cart),

              // --------------------------------------------------
              // CREDIT CUSTOMER WARNING
              // --------------------------------------------------
              if (needsCustomer &&
                  _method == _PaymentMethod.mixed &&
                  _mixedCredit > 0 &&
                  cart.selectedCustomer == null)
                _buildCreditSummary(cart),

              // --------------------------------------------------
              // ERROR
              // --------------------------------------------------
              if (_error != null) ...[
                SizedBox(height: 14),

                Container(
                  padding:
                      EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger
                        .withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color:
                          AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              SizedBox(height: 20),

              // --------------------------------------------------
              // CREATE BILL
              // --------------------------------------------------
              ElevatedButton(
                onPressed:
                    _submitting
                        ? null
                        : _createBill,
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        cart.orderType ==
                                'delivery'
                            ? 'PLACE DELIVERY ORDER'
                            : 'CREATE BILL',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchAndSelectCustomer() async {
    final controller = TextEditingController();
    List<Customer> results = [];
    bool loading = false;

    final selected = await showDialog<Customer>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> search() async {
              setDialogState(() => loading = true);
              try {
                results = await CustomerService().list(search: controller.text.trim());
              } catch (_) {
                results = [];
              } finally {
                if (ctx.mounted) setDialogState(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search customers by name or phone',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: loading ? null : search,
                        ),
                      ),
                      onSubmitted: (_) => search(),
                    ),
                    const SizedBox(height: 12),
                    if (loading) const LinearProgressIndicator(),
                    if (!loading && results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Search to find a customer.'),
                      ),
                    if (results.isNotEmpty)
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final customer = results[i];
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                              title: Text(customer.name),
                              subtitle: Text(customer.phone),
                              onTap: () => Navigator.pop(ctx, customer),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (selected != null && mounted) {
      context.read<CartProvider>().selectedCustomer = selected;
      context.read<CartProvider>().notifyListeners();
      setState(() {});
    }
  }

  Future<void> _splitBill() async {
    final cart = context.read<CartProvider>();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bill Splitting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Split ${Formatters.currency(cart.grandTotal)} among:'),
            const SizedBox(height: 14),
            for (final count in [2, 3, 4, 5])
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text('$count people'),
                trailing: Text(Formatters.currency(cart.grandTotal / count)),
                onTap: () => Navigator.pop(ctx, count),
              ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => _splitCount = result);
  }

  Future<void> _shareBillPreview(CartProvider cart) async {
    final buffer = StringBuffer()
      ..writeln('Fast N Fresh - Order')
      ..writeln('Bill: ${cart.tableCustomerLabel ?? cart.orderType}')
      ..writeln('---');
    for (final item in cart.items) {
      buffer.writeln('${item.product.name} x${item.quantity}  ${Formatters.currency(item.lineTotal)}');
    }
    buffer
      ..writeln('---')
      ..writeln('Subtotal: ${Formatters.currency(cart.subtotal)}')
      ..writeln('Total: ${Formatters.currency(_checkoutTax(cart))}');
    await Share.share(buffer.toString());
  }

  double _checkoutTax(CartProvider cart) {
    if (!_taxEnabled || _taxPercent <= 0) return cart.grandTotal;
    final taxable = (cart.subtotal - cart.discount).clamp(0, double.infinity).toDouble();
    return taxable + (taxable * _taxPercent / 100);
  }

  Widget _checkoutHeader(CartProvider cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shopping_cart_outlined, color: AppColors.primary, size: 23),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Checkout', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            ),
            IconButton(onPressed: _submitting ? null : () => _shareBillPreview(cart), icon: const Icon(Icons.local_offer_outlined)),
            IconButton(onPressed: _submitting ? null : _searchAndSelectCustomer, icon: const Icon(Icons.edit_outlined)),
            IconButton(onPressed: _submitting ? null : () => PrinterChoiceSheet.show(context), icon: const Icon(Icons.print_outlined)),
          ],
        ),
        const Divider(height: 22),
        Row(
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 20),
            const SizedBox(width: 8),
            Text('${cart.itemCount} items', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: 8),
            Text(_nowLabel(), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ],
    );
  }

  String _nowLabel() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    return '${now.day} ${_month(now.month)} ${now.year}, $h:$minute ${now.hour >= 12 ? 'pm' : 'am'}';
  }

  String _month(int month) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][month];

  Widget _checkoutSummary(CartProvider cart) {
    final taxable = (cart.subtotal - cart.discount).clamp(0, double.infinity).toDouble();
    final tax = _taxEnabled ? taxable * _taxPercent / 100 : 0.0;
    final total = taxable + tax;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...cart.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(9)),
                      child: Icon(Icons.image_outlined, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Text('${item.quantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 9),
                    Text(Formatters.currency(item.lineTotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              )),
          const Divider(height: 24),
          _summaryLine('Sub Total', Formatters.currency(cart.subtotal), bold: true),
          if (_taxEnabled) ...[
            _summaryLine('CGST (${(_taxPercent / 2).toStringAsFixed(2)}%)', Formatters.currency(tax / 2)),
            _summaryLine('SGST (${(_taxPercent / 2).toStringAsFixed(2)}%)', Formatters.currency(tax / 2)),
          ],
          if (cart.discount > 0) _summaryLine('Discount', '-${Formatters.currency(cart.discount)}'),
          const Divider(height: 24),
          _summaryLine('Grand Total', Formatters.currency(total), bold: true, primary: true, large: true),
          const SizedBox(height: 4),
          Center(child: Text('Printing is optional', style: TextStyle(color: AppColors.textMuted))),
          const SizedBox(height: 12),
          TextField(
            readOnly: true,
            onTap: _searchAndSelectCustomer,
            decoration: InputDecoration(
              hintText: cart.selectedCustomer == null ? 'Search customers by name or phone' : cart.selectedCustomer!.name,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: cart.selectedCustomer == null ? null : IconButton(onPressed: () { cart.selectedCustomer = null; cart.notifyListeners(); }, icon: const Icon(Icons.close)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.people_outline), SizedBox(width: 10), Text('Bill Splitting', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))]),
                const SizedBox(height: 9),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _submitting ? null : _splitBill, icon: const Icon(Icons.groups_outlined), label: Text(_splitCount > 1 ? 'Split Bill Among $_splitCount People' : 'Split Bill Among Multiple People'))),
                if (_splitCount > 1) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Each person: ${Formatters.currency(total / _splitCount)}', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Center(child: Text('Share Bill With Customer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _shareCircle(Icons.chat_outlined, 'WhatsApp', cart),
              _shareCircle(Icons.sms_outlined, 'Text', cart),
              _shareCircle(Icons.email_outlined, 'Email', cart),
              _shareCircle(Icons.download_outlined, 'Save', cart),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shareCircle(IconData icon, String label, CartProvider cart) {
    return InkWell(
      onTap: () => _shareBillPreview(cart),
      borderRadius: BorderRadius.circular(40),
      child: Column(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: Icon(icon, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _summaryLine(String label, String value, {bool bold = false, bool primary = false, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: large ? 17 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: large ? 19 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: primary ? AppColors.primary : null)),
        ],
      ),
    );
  }

  // ============================================================
  // MIXED PAYMENT
  // ============================================================

  Widget _buildMixedPayment(
    CartProvider cart,
  ) {
    final difference =
        cart.grandTotal - _mixedTotal;

    final complete =
        difference.abs() < 0.01;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter payment split',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),

        SizedBox(height: 10),

        // CASH
        TextField(
          controller:
              _mixedCashController,
          keyboardType:
              TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration:
              InputDecoration(
            labelText: 'Cash Amount',
            prefixIcon:
                Icon(Icons.payments_outlined),
          ),
          onChanged: (_) {
            setState(() {
              _error = null;
            });
          },
        ),

        SizedBox(height: 10),

        // UPI
        TextField(
          controller:
              _mixedUpiController,
          keyboardType:
              TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration:
              InputDecoration(
            labelText: 'UPI Amount',
            prefixIcon:
                Icon(Icons.qr_code_scanner),
          ),
          onChanged: (_) {
            setState(() {
              _error = null;
            });
          },
        ),

        SizedBox(height: 10),

        // CREDIT
        TextField(
          controller:
              _mixedCreditController,
          keyboardType:
              TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration:
              InputDecoration(
            labelText: 'Credit / UDHAR Amount',
            prefixIcon: Icon(
              Icons.account_balance_wallet_outlined,
            ),
          ),
          onChanged: (_) {
            setState(() {
              _error = null;
            });
          },
        ),

        SizedBox(height: 12),

        // PAYMENT SUMMARY
        Container(
          padding:
              EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.circular(10),
            border: Border.all(
              color: complete
                  ? AppColors.primary
                  : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              _kv(
                'Bill Total',
                Formatters.currency(
                  cart.grandTotal,
                ),
              ),

              _kv(
                'Cash',
                Formatters.currency(
                  _mixedCash,
                ),
              ),

              _kv(
                'UPI',
                Formatters.currency(
                  _mixedUpi,
                ),
              ),

              _kv(
                'Credit / UDHAR',
                Formatters.currency(
                  _mixedCredit,
                ),
              ),

              Divider(height: 14),

              _kv(
                'Entered',
                Formatters.currency(
                  _mixedTotal,
                ),
              ),

              Divider(height: 14),

              _kv(
                complete
                    ? 'Status'
                    : 'Remaining',
                complete
                    ? 'Complete'
                    : Formatters.currency(
                        difference.abs(),
                      ),
                bold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CREDIT SUMMARY
  // ============================================================

  Widget _buildCreditSummary(
    CartProvider cart,
  ) {
    final customer =
        cart.selectedCustomer;

    if (customer == null) {
      return Padding(
        padding:
            EdgeInsets.only(top: 4),
        child: Container(
          padding:
              EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.credit
                .withValues(alpha: 0.08),
            borderRadius:
                BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.credit,
                size: 18,
              ),

              SizedBox(width: 8),

              Expanded(
                child: Text(
                  'Select a customer from the cart screen to bill this on UDHAR.',
                  style: TextStyle(
                    color:
                        AppColors.credit,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final creditAmount =
        _method == _PaymentMethod.mixed
            ? _mixedCredit
            : cart.grandTotal;

    final newDue =
        customer.outstandingBalance +
            creditAmount;

    return Padding(
      padding:
          EdgeInsets.only(top: 4),
      child: Container(
        padding:
            EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Customer: ${customer.name}',
              style: TextStyle(
                fontWeight:
                    FontWeight.w700,
              ),
            ),

            SizedBox(height: 8),

            _kv(
              'Previous Due',
              Formatters.currency(
                customer.outstandingBalance,
              ),
            ),

            _kv(
              'Current Credit',
              Formatters.currency(
                creditAmount,
              ),
            ),

            Divider(height: 16),

            _kv(
              'New Due',
              Formatters.currency(
                newDue,
              ),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // KEY / VALUE ROW
  // ============================================================

  Widget _kv(
    String key,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding:
          EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              key,
              style: TextStyle(
                fontSize:
                    bold ? 14 : 13,
                color: bold
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: bold
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),

          SizedBox(width: 12),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize:
                    bold ? 15 : 13,
                color: bold
                    ? AppColors.credit
                    : AppColors.textPrimary,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAYMENT METHOD BUTTON
  // ============================================================

  Widget _methodButton(
    String label,
    IconData icon,
    Color color,
    _PaymentMethod method,
  ) {
    final selected =
        _method == method;

    return InkWell(
      onTap: _submitting
          ? null
          : () {
              setState(() {
                _method = method;
                _error = null;
              });
            },
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        padding:
            EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(
                  alpha: 0.1,
                )
              : AppColors.surface,
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color
                : AppColors.border,
            width:
                selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? color
                  : AppColors.textSecondary,
              size: 21,
            ),

            SizedBox(height: 5),

            Text(
              label,
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color: selected
                    ? color
                    : AppColors.textSecondary,
                fontWeight:
                    FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}