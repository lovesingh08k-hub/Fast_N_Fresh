import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../models/order.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/order_service.dart';

import 'bill_success_screen.dart';

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
    if (_method == _PaymentMethod.upi && _upiRefController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter the UPI reference / UTR before completing the bill.';
      });
      return;
    }

    if (_method == _PaymentMethod.mixed && _mixedUpi > 0 && _upiRefController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter the UPI reference / UTR for the UPI portion.';
      });
      return;
    }

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
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          24,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
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
                  fontSize: 18,
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
                        'UPI Reference / UTR (required)',
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