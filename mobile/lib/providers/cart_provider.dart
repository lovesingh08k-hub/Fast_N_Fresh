import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../services/order_service.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/customer.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  /// Flat discount in ₹ (when [discountType] is 'flat').
  double discount = 0;
  String notes = '';

  // ------------------------------------------------------------
  // BILL ADJUSTMENTS (see backend services/billing.js)
  // ------------------------------------------------------------

  /// 'flat' = [discount] in ₹, 'percent' = [discountPercent] of the subtotal.
  String discountType = 'flat';
  double discountPercent = 0;
  String discountReason = '';

  /// Service charge on/off for this bill; null = the outlet's default.
  bool? serviceChargeOn;

  /// Delivery charge for this bill; null = the outlet's default.
  double? deliveryChargeOverride;

  /// The server's calculation of the current cart (GST, charges,
  /// round-off). Refreshed automatically shortly after every change.
  BillBreakdown? quote;
  String? _quoteKey;
  Timer? _quoteTimer;

  /// Turned off in widget tests that have no server.
  static bool autoQuote = true;

  /// Adjustment fields sent with quote / bill / open-order requests.
  Map<String, dynamic> get billAdjustments => {
        'discountType': discountType,
        'discountValue': discountType == 'percent' ? discountPercent : discount,
        if (discountType == 'flat') 'discount': discount,
        'discountReason': discountReason.trim(),
        if (serviceChargeOn != null) 'serviceCharge': serviceChargeOn,
        if (deliveryChargeOverride != null) 'deliveryCharge': deliveryChargeOverride,
      };

  String get _currentQuoteKey => [
        orderType,
        for (final i in _items.values) '${i.product.id}x${i.quantity}',
        billAdjustments.toString(),
      ].join('|');

  /// Whether [quote] matches the cart as it is now.
  bool get quoteIsCurrent => quote != null && _quoteKey == _currentQuoteKey;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleQuote();
  }

  void _scheduleQuote() {
    if (!autoQuote || _items.isEmpty) return;
    final key = _currentQuoteKey;
    if (key == _quoteKey) return;
    _quoteTimer?.cancel();
    _quoteTimer = Timer(const Duration(milliseconds: 250), () => _fetchQuote(key));
  }

  Future<void> _fetchQuote(String key) async {
    try {
      final result = await OrderService().quote(
        items: _items.values.toList(),
        orderType: orderType,
        adjust: billAdjustments,
      );
      if (key != _currentQuoteKey) return; // cart changed meanwhile
      quote = result;
      _quoteKey = key;
      super.notifyListeners();
    } catch (_) {
      // Offline/server error: totals fall back to the local subtotal.
    }
  }

  Customer? selectedCustomer;

  // ------------------------------------------------------------
  // DELIVERY
  // ------------------------------------------------------------

  String deliveryAddress = '';
  String deliveryPhone = '';

  // ------------------------------------------------------------
  // ORDER CONTEXT
  // ------------------------------------------------------------

  /// Supported values:
  /// dine_in
  /// takeaway
  /// delivery
  String orderType = 'takeaway';

  String? tableId;
  String? tableName;
  String? tableCustomerLabel;

  /// Optional customer name typed at order time (no customer record needed).
  /// When set it replaces the automatic "Customer N" label on the bill/KOT.
  String customerNameInput = '';

  /// Takeaway/Delivery counter slots: T1, T2... and D1, D2...
  static final RegExp slotPattern = RegExp(r'^[TD]\d+$');

  /// True when this Takeaway/Delivery cart sits in a counter slot (T1/D1).
  bool get hasSlot =>
      orderType != 'dine_in' &&
      tableCustomerLabel != null &&
      slotPattern.hasMatch(tableCustomerLabel!);

  /// Label sent to the server: the typed name, else the automatic label.
  /// A counter slot keeps its tag in front of the name ("T1 · Rahul") so
  /// the order stays in its slot.
  String? get effectiveCustomerLabel {
    final typed = customerNameInput.trim();
    if (hasSlot) {
      return typed.isNotEmpty ? '$tableCustomerLabel · $typed' : tableCustomerLabel;
    }
    return typed.isNotEmpty ? typed : tableCustomerLabel;
  }

  /// Label to send when updating an already-open order. Outside a slot only
  /// a typed name is sent, so an empty field never wipes the stored label.
  String get openOrderLabelUpdate =>
      hasSlot ? effectiveCustomerLabel! : customerNameInput;

  void setCustomerNameInput(String value) {
    customerNameInput = value;
    notifyListeners();
  }

  /// ID of an existing OPEN Dine-In order.
  ///
  /// null means this is a normal/direct order.
  String? openOrderId;

  // ------------------------------------------------------------
  // GETTERS
  // ------------------------------------------------------------

  List<CartItem> get items =>
      _items.values.toList();

  bool get isEmpty =>
      _items.isEmpty;

  int get itemCount =>
      _items.values.fold(
        0,
        (sum, item) => sum + item.quantity,
      );

  double get subtotal =>
      _items.values.fold(
        0.0,
        (sum, item) => sum + item.lineTotal,
      );

  /// Amount to pay: the server's calculation when it is current, otherwise
  /// the local subtotal less a flat discount (no GST/charges).
  double get grandTotal => quoteIsCurrent ? quote!.grandTotal : _localTotal;

  double get _localTotal =>
      (subtotal - discount)
          .clamp(
            0,
            double.infinity,
          )
          .toDouble();

  // ------------------------------------------------------------
  // ORDER CONTEXT
  // ------------------------------------------------------------

  /// Configures the current cart for:
  ///
  /// - Takeaway
  /// - Delivery
  /// - Dine-In
  /// - Existing open Dine-In order
  void configureContext({
    required String orderType,
    String? tableId,
    String? tableName,
    String? tableCustomerLabel,
    String? openOrderId,
  }) {
    this.orderType = orderType;

    this.tableId = tableId;
    this.tableName = tableName;
    this.tableCustomerLabel =
        tableCustomerLabel;
    customerNameInput = '';

    this.openOrderId = openOrderId;

    // Delivery details should not accidentally
    // carry over from another order type.
    if (orderType != 'delivery') {
      deliveryAddress = '';
      deliveryPhone = '';
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // OPEN DINE-IN ORDER
  // ------------------------------------------------------------

  /// Restores an existing OPEN Dine-In order
  /// into the cart.
  void hydrateFromOpenOrder({
    required List<CartItem> items,
    required double discount,
    Customer? customer,
  }) {
    _items.clear();

    for (final item in items) {
      _items[item.product.id] = item;
    }

    this.discount = discount;

    selectedCustomer = customer;

    // Open Dine-In orders must never
    // accidentally retain delivery information.
    deliveryAddress = '';
    deliveryPhone = '';

    notifyListeners();
  }

  // ------------------------------------------------------------
  // PRODUCTS
  // ------------------------------------------------------------

  void addProduct(Product product) {
    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity += 1;
    } else {
      _items[product.id] =
          CartItem(product: product);
    }

    notifyListeners();
  }

  void incrementQuantity(
    String productId,
  ) {
    final item =
        _items[productId];

    if (item == null) return;

    item.quantity += 1;

    notifyListeners();
  }

  void decrementQuantity(
    String productId,
  ) {
    final item =
        _items[productId];

    if (item == null) return;

    if (item.quantity <= 1) {
      _items.remove(productId);
    } else {
      item.quantity -= 1;
    }

    notifyListeners();
  }

  void removeItem(
    String productId,
  ) {
    _items.remove(productId);

    notifyListeners();
  }

  // ------------------------------------------------------------
  // DISCOUNT
  // ------------------------------------------------------------

  void _resetAdjustments() {
    discountType = 'flat';
    discountPercent = 0;
    discountReason = '';
    serviceChargeOn = null;
    deliveryChargeOverride = null;
    quote = null;
    _quoteKey = null;
    _quoteTimer?.cancel();
  }

  void setPercentDiscount(double percent) {
    discountType = 'percent';
    discountPercent = percent.clamp(0, 100).toDouble();
    discount = 0;
    notifyListeners();
  }

  void setDiscountReason(String value) {
    discountReason = value;
    notifyListeners();
  }

  void setServiceCharge(bool? value) {
    serviceChargeOn = value;
    notifyListeners();
  }

  void setDeliveryCharge(double? value) {
    deliveryChargeOverride = value;
    notifyListeners();
  }

  void setItemNote(String productId, String note) {
    final item = _items[productId];
    if (item == null) return;
    item.note = note;
    notifyListeners();
  }

  /// Restores the discount/charge choices saved on an open order.
  void restoreAdjustments(BillBreakdown bill, {bool? serviceCharge, double? deliveryCharge}) {
    discountType = bill.discountType;
    if (bill.discountType == 'percent') {
      discountPercent = bill.discountValue;
      discount = 0;
    } else {
      discount = bill.discount;
    }
    discountReason = bill.discountReason ?? '';
    serviceChargeOn = serviceCharge;
    deliveryChargeOverride = deliveryCharge;
    notifyListeners();
  }

  void setDiscount(
    double value,
  ) {
    discountType = 'flat';
    discount =
        value < 0 ? 0 : value;

    // Discount can never be greater
    // than subtotal.
    if (discount > subtotal) {
      discount = subtotal;
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // NOTES
  // ------------------------------------------------------------

  void setNotes(
    String value,
  ) {
    notes = value;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // CUSTOMER
  // ------------------------------------------------------------

  void setCustomer(
    Customer? customer,
  ) {
    selectedCustomer = customer;

    // When selecting a customer for delivery,
    // automatically use saved customer details
    // if delivery fields are currently empty.
    if (orderType == 'delivery' &&
        customer != null) {
      if (deliveryAddress.trim().isEmpty) {
        deliveryAddress =
            customer.address?.trim() ?? '';
      }

      if (deliveryPhone.trim().isEmpty) {
        deliveryPhone =
            customer.phone.trim();
      }
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // DELIVERY
  // ------------------------------------------------------------

  void setDeliveryAddress(
    String value,
  ) {
    deliveryAddress = value;

    notifyListeners();
  }

  void setDeliveryPhone(
    String value,
  ) {
    deliveryPhone = value;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // CLEAR ITEMS
  // ------------------------------------------------------------

  /// Clears bill/cart information while
  /// keeping the current order context.
  ///
  /// Useful when the screen needs to retain
  /// the current table/order context.
  void clearItems() {
    _items.clear();

    discount = 0;
    notes = '';
    _resetAdjustments();

    selectedCustomer = null;

    deliveryAddress = '';
    deliveryPhone = '';

    notifyListeners();
  }

  // ------------------------------------------------------------
  // COMPLETE RESET
  // ------------------------------------------------------------

  /// Completely resets the cart.
  ///
  /// Used after successful billing.
  void clear() {
    _items.clear();

    discount = 0;
    notes = '';
    _resetAdjustments();

    selectedCustomer = null;

    deliveryAddress = '';
    deliveryPhone = '';

    orderType = 'takeaway';

    tableId = null;
    tableName = null;
    tableCustomerLabel = null;
    customerNameInput = '';

    openOrderId = null;

    notifyListeners();
  }
}