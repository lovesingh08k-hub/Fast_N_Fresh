import 'package:flutter_test/flutter_test.dart';
import 'package:pwp_pos/models/bill.dart';
import 'package:pwp_pos/models/order.dart';
import 'package:pwp_pos/models/product.dart';
import 'package:pwp_pos/providers/cart_provider.dart';
import 'package:pwp_pos/services/receipt_service.dart';

void main() {
  setUp(() => CartProvider.autoQuote = false);

  test('bill rows: discount, service charge, CGST/SGST per rate, round-off', () {
    final bill = BillBreakdown.fromJson({
      'subtotal': 300,
      'discount': 30,
      'discountType': 'percent',
      'discountValue': 10,
      'discountReason': 'Regular',
      'serviceCharge': 27,
      'serviceChargePercent': 10,
      'taxes': [
        {'rate': 5, 'taxable': 207, 'cgst': 5.18, 'sgst': 5.17, 'tax': 10.35},
        {'rate': 18, 'taxable': 90, 'cgst': 8.1, 'sgst': 8.1, 'tax': 16.2},
      ],
      'roundOff': 0.45,
      'grandTotal': 324,
    });
    final labels = bill.rows().map((r) => r.$1).toList();
    expect(labels, [
      'Discount (10%) - Regular',
      'Service charge (10%)',
      'CGST 2.5%',
      'SGST 2.5%',
      'CGST 9%',
      'SGST 9%',
      'Round off',
    ]);
    expect(bill.rows().first.$2, -30);
  });

  test('IGST bills show one IGST line per rate', () {
    final bill = BillBreakdown.fromJson({
      'taxes': [
        {'rate': 12, 'taxable': 100, 'igst': 12, 'tax': 12},
      ],
    });
    expect(bill.rows().map((r) => r.$1), ['IGST 12%']);
  });

  test('cart sends ₹ or % discount, reason and service-charge choice', () {
    final cart = CartProvider()..addProduct(Product(id: 'p1', name: 'Tea', categoryId: 'c', sellingPrice: 20));
    cart.setDiscount(15);
    expect(cart.billAdjustments['discountType'], 'flat');
    expect(cart.billAdjustments['discountValue'], 15);

    cart
      ..setPercentDiscount(10)
      ..setDiscountReason('Staff')
      ..setServiceCharge(false);
    expect(cart.billAdjustments['discountType'], 'percent');
    expect(cart.billAdjustments['discountValue'], 10);
    expect(cart.billAdjustments['discountReason'], 'Staff');
    expect(cart.billAdjustments['serviceCharge'], false);

    cart.clear();
    expect(cart.billAdjustments['discountType'], 'flat');
    expect(cart.billAdjustments.containsKey('serviceCharge'), isFalse);
  });

  test('payment labels for the new payment modes', () {
    Order order(String method, {Map<String, dynamic> extra = const {}}) => Order.fromJson({
          '_id': 'o1',
          'orderNumber': 1,
          'items': [],
          'paymentMethod': method,
          'createdAt': '2026-10-29T10:00:00Z',
          ...extra,
        });
    expect(ReceiptService.paymentLabel(order('CARD')), 'Card');
    expect(ReceiptService.paymentLabel(order('ONLINE', extra: {'onlinePlatform': 'Swiggy'})), 'Online (Swiggy)');
    expect(ReceiptService.paymentLabel(order('COMPLIMENTARY')), 'Complimentary');
    expect(
      ReceiptService.paymentLabel(order('MIXED', extra: {
        'paymentBreakdown': {'cash': 100, 'card': 121},
      })),
      'Mixed (Cash 100, Card 121)',
    );
  });
}
