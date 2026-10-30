/// GST on one rate of a bill: taxable value and CGST/SGST (same state) or
/// IGST (other state).
class TaxLine {
  final double rate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double tax;

  const TaxLine({required this.rate, this.taxable = 0, this.cgst = 0, this.sgst = 0, this.igst = 0, this.tax = 0});

  factory TaxLine.fromJson(Map<String, dynamic> j) => TaxLine(
        rate: _d(j['rate']),
        taxable: _d(j['taxable']),
        cgst: _d(j['cgst']),
        sgst: _d(j['sgst']),
        igst: _d(j['igst']),
        tax: _d(j['tax']),
      );

  bool get isIgst => igst > 0 && cgst == 0;
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// How a bill adds up (server calculation, see backend services/billing):
/// items -> discount -> service/packaging/delivery charges -> GST -> round-off.
/// Used for a saved order and for the live preview while billing.
class BillBreakdown {
  final double subtotal;
  final double discount;
  final String discountType; // flat | percent
  final double discountValue;
  final String? discountReason;
  final bool complimentary;
  final double serviceCharge;
  final double serviceChargePercent;
  final double packagingCharge;
  final double deliveryCharge;
  final double taxableAmount;
  final List<TaxLine> taxes;
  final double tax;
  final bool taxInclusive;
  final double roundOff;
  final double grandTotal;

  const BillBreakdown({
    this.subtotal = 0,
    this.discount = 0,
    this.discountType = 'flat',
    this.discountValue = 0,
    this.discountReason,
    this.complimentary = false,
    this.serviceCharge = 0,
    this.serviceChargePercent = 0,
    this.packagingCharge = 0,
    this.deliveryCharge = 0,
    this.taxableAmount = 0,
    this.taxes = const [],
    this.tax = 0,
    this.taxInclusive = false,
    this.roundOff = 0,
    this.grandTotal = 0,
  });

  factory BillBreakdown.fromJson(Map<String, dynamic> j) {
    final reason = j['discountReason']?.toString().trim();
    return BillBreakdown(
      subtotal: _d(j['subtotal']),
      discount: _d(j['discount']),
      discountType: j['discountType']?.toString() == 'percent' ? 'percent' : 'flat',
      discountValue: _d(j['discountValue']),
      discountReason: reason == null || reason.isEmpty ? null : reason,
      complimentary: j['complimentary'] == true,
      serviceCharge: _d(j['serviceCharge']),
      serviceChargePercent: _d(j['serviceChargePercent']),
      packagingCharge: _d(j['packagingCharge']),
      deliveryCharge: _d(j['deliveryCharge']),
      taxableAmount: _d(j['taxableAmount']),
      taxes: (j['taxes'] as List? ?? const [])
          .whereType<Map>()
          .map((t) => TaxLine.fromJson(Map<String, dynamic>.from(t)))
          .toList(),
      tax: _d(j['tax']),
      taxInclusive: j['taxInclusive'] == true,
      roundOff: _d(j['roundOff']),
      grandTotal: _d(j['grandTotal']),
    );
  }

  bool get hasCharges => serviceCharge > 0 || packagingCharge > 0 || deliveryCharge > 0;

  /// Rows to print/show between Subtotal and Grand Total, in bill order.
  List<(String label, double amount)> rows() {
    final list = <(String, double)>[];
    if (discount > 0) {
      final pct = discountType == 'percent' && !complimentary ? ' (${_trim(discountValue)}%)' : '';
      final why = complimentary ? 'Complimentary' : 'Discount$pct';
      list.add((discountReason != null && !complimentary ? '$why - $discountReason' : why, -discount));
    }
    if (serviceCharge > 0) list.add(('Service charge (${_trim(serviceChargePercent)}%)', serviceCharge));
    if (packagingCharge > 0) list.add(('Packaging', packagingCharge));
    if (deliveryCharge > 0) list.add(('Delivery charge', deliveryCharge));
    for (final t in taxes) {
      if (t.isIgst) {
        list.add(('IGST ${_trim(t.rate)}%', t.igst));
      } else {
        list.add(('CGST ${_trim(t.rate / 2)}%', t.cgst));
        list.add(('SGST ${_trim(t.rate / 2)}%', t.sgst));
      }
    }
    if (roundOff != 0) list.add(('Round off', roundOff));
    return list;
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
