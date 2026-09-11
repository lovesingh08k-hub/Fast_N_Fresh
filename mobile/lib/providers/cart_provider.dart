import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/customer.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  double discount = 0;
  String notes = '';

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

  double get grandTotal =>
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

  void setDiscount(
    double value,
  ) {
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
            customer.phone?.trim() ?? '';
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

    selectedCustomer = null;

    deliveryAddress = '';
    deliveryPhone = '';

    orderType = 'takeaway';

    tableId = null;
    tableName = null;
    tableCustomerLabel = null;

    openOrderId = null;

    notifyListeners();
  }
}