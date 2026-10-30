import '../core/network/dio_client.dart';
import '../models/order.dart';
import '../models/bill.dart';
import '../models/cart_item.dart';

class OrderService {
  final _dio = DioClient.instance.dio;

  /// Cart lines as the API expects them (menu item or quick item, with the
  /// kitchen note). Prices are never sent; the server takes them from the menu.
  static List<Map<String, dynamic>> itemsPayload(List<CartItem> items) => items
      .map((item) => {
            if (item.product.id.startsWith('quick:'))
              'quickItem': {'name': item.product.name, 'price': item.product.sellingPrice}
            else
              'productId': item.product.id,
            'quantity': item.quantity,
            if (item.note.trim().isNotEmpty) 'note': item.note.trim(),
          })
      .toList();

  /// Bill preview (GST, charges, round-off) exactly as the final bill will
  /// be calculated; nothing is saved. [adjust] = discount/charge choices.
  Future<BillBreakdown> quote({
    required List<CartItem> items,
    required String orderType,
    Map<String, dynamic> adjust = const {},
  }) async {
    try {
      final res = await _dio.post('/orders/quote', data: {
        'items': itemsPayload(items),
        'orderType': orderType,
        ...adjust,
      });
      return BillBreakdown.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Moves some lines ({index, quantity}) of an open order to a new open order.
  Future<Order> splitOpenOrder(String orderId, List<Map<String, int>> lines, {String? label}) async {
    try {
      final res = await _dio.post('/orders/$orderId/split', data: {
        'lines': lines,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      });
      return Order.fromJson(res.data['data']['newOrder'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Moves every item of [fromOrderId] into [orderId] and closes the other order.
  Future<Order> mergeOpenOrders(String orderId, String fromOrderId) async {
    try {
      final res = await _dio.post('/orders/$orderId/merge', data: {'fromOrderId': fromOrderId});
      return Order.fromJson(res.data['data']['order'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Creates a completed bill.
  ///
  /// Used for:
  /// - Takeaway
  /// - Delivery
  /// - Quick Dine-In
  ///
  /// The backend recalculates prices, subtotal, discount and grand total.
  /// The client only sends product IDs and quantities.
  ///
  /// [clientRequestId] should be a UUID generated once per checkout attempt
  /// by the caller and reused unchanged if the same bill is retried.
  Future<Order> createOrder({
    required List<CartItem> items,
    required double discount,
    required String paymentMethod,
    double? amountReceived,
    String? upiReference,
    String? customerId,
    String? notes,
    double? cashPortion,
    double? upiPortion,
    double? creditPortion,
    String orderType = 'takeaway',
    String? tableId,
    String? tableCustomerLabel,
    Map<String, String>? deliveryInfo,
    String? clientRequestId,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final res = await _dio.post(
        '/orders',
        data: {
          'items': itemsPayload(items),
          'discount': discount,
          'paymentMethod': paymentMethod,
          if (amountReceived != null) 'amountReceived': amountReceived,
          if (upiReference != null && upiReference.trim().isNotEmpty)
            'upiReference': upiReference.trim(),
          if (customerId != null && customerId.trim().isNotEmpty)
            'customerId': customerId,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
          if (cashPortion != null) 'cashPortion': cashPortion,
          if (upiPortion != null) 'upiPortion': upiPortion,
          if (creditPortion != null) 'creditPortion': creditPortion,
          'orderType': orderType,
          if (tableId != null && tableId.trim().isNotEmpty)
            'tableId': tableId,
          if (tableCustomerLabel != null &&
              tableCustomerLabel.trim().isNotEmpty)
            'tableCustomerLabel': tableCustomerLabel,
          if (deliveryInfo != null) 'deliveryInfo': deliveryInfo,
          if (clientRequestId != null &&
              clientRequestId.trim().isNotEmpty)
            'clientRequestId': clientRequestId,
          ...extra,
        },
      );

      final responseData = res.data['data'] as Map<String, dynamic>;
      final orderData =
          responseData['order'] as Map<String, dynamic>;

      return Order.fromJson(orderData);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Starts a Shopto-style unpaid operational order/tab.
  ///
  /// Unlike the public QR flow, this is only for authenticated POS staff.
  /// The order can be edited, sent to kitchen in one or more KOTs, and paid
  /// later from Orders/Order Detail.
  Future<Order> startOpenOrder({
    required String orderType,
    String? tableId,
    String? tableCustomerLabel,
    String? customerId,
    Map<String, String>? deliveryInfo,
    String? notes,
  }) async {
    try {
      final res = await _dio.post('/orders/open', data: {
        'orderType': orderType,
        if (tableId != null && tableId.trim().isNotEmpty) 'tableId': tableId,
        if (tableCustomerLabel != null && tableCustomerLabel.trim().isNotEmpty)
          'tableCustomerLabel': tableCustomerLabel.trim(),
        if (customerId != null && customerId.trim().isNotEmpty) 'customerId': customerId,
        if (deliveryInfo != null) 'deliveryInfo': deliveryInfo,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      return Order.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Updates an existing OPEN Dine-In order.
  ///
  /// This does NOT:
  /// - deduct inventory
  /// - create a credit transaction
  /// - complete payment
  ///
  /// Those operations happen during checkoutOrder().
  Future<Order> updateOpenOrderItems(
    String orderId, {
    required List<CartItem> items,
    required double discount,
    String? notes,
    String? customerId,
    String? tableCustomerLabel,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final res = await _dio.put(
        '/orders/$orderId/items',
        data: {
          'items': itemsPayload(items),
          'discount': discount,
          if (notes != null) 'notes': notes,
          if (customerId != null && customerId.trim().isNotEmpty)
            'customerId': customerId,
          if (tableCustomerLabel != null && tableCustomerLabel.trim().isNotEmpty)
            'tableCustomerLabel': tableCustomerLabel.trim(),
          ...extra,
        },
      );

      final data = res.data['data'] as Map<String, dynamic>;

      return Order.fromJson(data);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Finalizes an OPEN Dine-In order.
  ///
  /// Supported payment methods:
  /// CASH
  /// UPI
  /// CREDIT
  /// MIXED
  ///
  /// For MIXED:
  /// cashPortion + upiPortion + creditPortion
  /// must equal the final bill total.
  Future<Order> checkoutOrder(
    String orderId, {
    required String paymentMethod,
    double? amountReceived,
    String? upiReference,
    String? customerId,
    double? cashPortion,
    double? upiPortion,
    double? creditPortion,
    double? discount,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final res = await _dio.post(
        '/orders/$orderId/checkout',
        data: {
          'paymentMethod': paymentMethod,
          if (amountReceived != null) 'amountReceived': amountReceived,
          if (upiReference != null && upiReference.trim().isNotEmpty)
            'upiReference': upiReference.trim(),
          if (customerId != null && customerId.trim().isNotEmpty)
            'customerId': customerId,
          if (cashPortion != null) 'cashPortion': cashPortion,
          if (upiPortion != null) 'upiPortion': upiPortion,
          if (creditPortion != null) 'creditPortion': creditPortion,
          if (discount != null) 'discount': discount,
          ...extra,
        },
      );

      final data = res.data['data'] as Map<String, dynamic>;
      final orderData = data['order'] as Map<String, dynamic>;

      return Order.fromJson(orderData);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Cancels an OPEN unpaid Dine-In order.
  ///
  /// This does not reverse inventory or credit because
  /// those are only applied at checkout.
  Future<void> cancelOpenOrder(
    String orderId, {
    String? reason,
  }) async {
    try {
      await _dio.delete(
        '/orders/$orderId',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Reassigns an order to another employee.
  ///
  /// Backend allows only admin/manager.
  Future<void> reassignAttendee(
    String orderId,
    String userId,
  ) async {
    try {
      await _dio.patch(
        '/orders/$orderId/attendee',
        data: {
          'userId': userId,
        },
      );
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> shiftOrderToTable(String orderId, String tableId) async {
    try {
      await _dio.patch('/orders/$orderId/table', data: {'tableId': tableId});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> updateOpenOrderNotes(String orderId, String notes) async {
    try {
      await _dio.patch('/orders/$orderId/notes', data: {'notes': notes});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> updateOpenOrderCustomer(String orderId, String customerId) async {
    try {
      await _dio.patch('/orders/$orderId/customer', data: {'customerId': customerId});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Gets order history.
  Future<List<Order>> list({
    DateTime? from,
    DateTime? to,
    String? paymentMethod,
    String? staffId,
    String? customerId,
    String? search,
    String? orderType,
    String? tableId,
    String? status,
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final res = await _dio.get(
        '/orders',
        queryParameters: {
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
          if (paymentMethod != null)
            'paymentMethod': paymentMethod,
          if (staffId != null) 'staff': staffId,
          if (customerId != null) 'customer': customerId,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (orderType != null) 'orderType': orderType,
          if (tableId != null) 'table': tableId,
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final list = res.data['data'] as List<dynamic>;

      return list
          .map(
            (item) => Order.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Gets one order by ID.
  Future<Order> getById(String id) async {
    try {
      final res = await _dio.get(
        '/orders/$id',
      );

      final data = res.data['data'] as Map<String, dynamic>;

      return Order.fromJson(data);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Advances a customer QR order through
  /// kitchen/service status.
  ///
  /// Valid workflow:
  /// open -> preparing -> ready
  ///
  /// Final payment changes it to completed.
  /// Advances an active order through the kitchen lifecycle:
  /// open -> preparing -> ready.
  ///
  /// Customer QR orders only. Normal staff/POS/table orders do not use
  /// the kitchen lifecycle because the KDS was removed from the staff APK.
  Future<Order> advanceKitchenStatus(
    String orderId,
    String status,
  ) async {
    try {
      final res = await _dio.patch(
        '/orders/$orderId/qr-status',
        data: {'status': status},
      );

      return Order.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Backward-compatible alias used by the QR order detail workflow only.
  Future<Order> updateQrStatus(String orderId, String status) =>
      advanceKitchenStatus(orderId, status);

  /// Voids a completed order.
  ///
  /// Backend allows only admin.
  ///
  /// Inventory is restored and credit ledger
  /// is reversed by the backend.
  /// Legacy KOT endpoint. The staff APK no longer exposes a KOT/KDS action.
  /// QR orders retain their server-side KOT flow; normal POS/table orders
  /// must not call this method from the staff UI.
  Future<Order> sendKot(String orderId) async {
    try {
      final res = await _dio.post('/orders/$orderId/kot');
      return Order.fromJson((res.data['data'] as Map<String, dynamic>)['order'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<Order> updateKitchenStatus(String orderId, String status) async {
    try {
      final res = await _dio.patch(
        '/orders/$orderId/kitchen-status',
        data: {'status': status},
      );
      return Order.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Gets orders for the Kitchen Display System.
  Future<List<Order>> kitchenOrders() async {
    try {
      final res = await _dio.get('/kds/orders');

      final list =
          (res.data['data'] as List<dynamic>? ?? []);

      return list
          .map(
            (e) => Order.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .where((order) => order.isQrOrder)
          .toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }


}