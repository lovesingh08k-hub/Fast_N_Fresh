import '../core/network/dio_client.dart';
import '../models/order.dart';
import '../models/cart_item.dart';

class OrderService {
  final _dio = DioClient.instance.dio;

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
  }) async {
    try {
      final res = await _dio.post(
        '/orders',
        data: {
          'items': items
              .map(
                (item) => {
                  'productId': item.product.id,
                  'quantity': item.quantity,
                },
              )
              .toList(),
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
  }) async {
    try {
      final res = await _dio.put(
        '/orders/$orderId/items',
        data: {
          'items': items
              .map(
                (item) => {
                  'productId': item.product.id,
                  'quantity': item.quantity,
                },
              )
              .toList(),
          'discount': discount,
          if (notes != null) 'notes': notes,
          if (customerId != null && customerId.trim().isNotEmpty)
            'customerId': customerId,
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
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final res = await _dio.get(
        '/orders',
        queryParameters: {
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          if (paymentMethod != null)
            'paymentMethod': paymentMethod,
          if (staffId != null) 'staff': staffId,
          if (customerId != null) 'customer': customerId,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (orderType != null) 'orderType': orderType,
          if (tableId != null) 'table': tableId,
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
  Future<Order> updateQrStatus(
    String orderId,
    String status,
  ) async {
    try {
      final res = await _dio.patch(
        '/orders/$orderId/qr-status',
        data: {
          'status': status,
        },
      );

      return Order.fromJson(
        res.data['data'] as Map<String, dynamic>,
      );
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  /// Voids a completed order.
  ///
  /// Backend allows only admin.
  ///
  /// Inventory is restored and credit ledger
  /// is reversed by the backend.
  Future<void> voidOrder(
    String id, {
    String? reason,
  }) async {
    try {
      await _dio.post(
        '/orders/$id/void',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
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
          .toList();
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }


}