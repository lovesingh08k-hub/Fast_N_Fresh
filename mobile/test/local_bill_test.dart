import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwp_pos/core/offline/local_bill.dart';

/// An offline receipt must match what the server would have calculated.
/// test/fixtures/bill_cases.json holds random bills worked out by the backend
/// (services/billing.js); regenerate it whenever that calculation changes.
void main() {
  final cases = jsonDecode(File('test/fixtures/bill_cases.json').readAsStringSync()) as List;

  test('the app calculates every bill exactly like the server', () {
    expect(cases.length, 500);
    for (var i = 0; i < cases.length; i++) {
      final c = (cases[i] as Map).cast<String, dynamic>();
      final bill = computeLocalBill(
        lines: (c['lines'] as List).map((l) => (l as Map).cast<String, dynamic>()).toList(),
        settings: (c['settings'] as Map).cast<String, dynamic>(),
        orderType: c['orderType'] as String,
        adjust: (c['adjust'] as Map).cast<String, dynamic>(),
      );
      final expected = (c['expected'] as Map).cast<String, dynamic>();
      for (final key in const [
        'subtotal', 'discount', 'discountValue', 'serviceCharge', 'serviceChargePercent', 'packagingCharge',
        'deliveryCharge', 'taxableAmount', 'tax', 'roundOff', 'grandTotal',
      ]) {
        expect((bill[key] as num).toDouble(), (expected[key] as num).toDouble(), reason: 'case $i: $key');
      }
      expect(bill['discountType'], expected['discountType'], reason: 'case $i');
      expect(bill['complimentary'], expected['complimentary'], reason: 'case $i');
      expect(bill['taxInclusive'], expected['taxInclusive'], reason: 'case $i');
      final taxes = bill['taxes'] as List;
      final expectedTaxes = expected['taxes'] as List;
      expect(taxes.length, expectedTaxes.length, reason: 'case $i: tax lines');
      for (var t = 0; t < taxes.length; t++) {
        for (final key in const ['rate', 'taxable', 'cgst', 'sgst', 'igst', 'tax']) {
          expect(((taxes[t] as Map)[key] as num).toDouble(), ((expectedTaxes[t] as Map)[key] as num).toDouble(), reason: 'case $i: tax $key');
        }
      }
      final lines = bill['orderItems'] as List;
      expect(lines.map((l) => (l as Map)['total']).toList(), (c['lineTotals'] as List).map((v) => (v as num).toDouble()).toList(), reason: 'case $i');
    }
  });

  test('CGST and SGST are always equal', () {
    final bill = computeLocalBill(
      lines: [
        {'name': 'A', 'price': 149.99, 'quantity': 3, 'taxRate': 5},
      ],
      settings: const {'taxEnabled': true, 'taxPercent': 5, 'roundOff': false},
    );
    final line = (bill['taxes'] as List).single as Map;
    expect(line['cgst'], line['sgst']);
    expect(round2((line['cgst'] as double) * 2), line['tax']);
  });

  test('round2 rounds halves like the server, also below zero', () {
    expect(round2(1.005), 1.01);
    expect(round2(2.675), 2.68);
    expect(round2(-0.125), -0.12);
  });
}
