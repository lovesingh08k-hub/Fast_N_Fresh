/// The bill calculation of backend `services/billing.js`, for when the server
/// cannot be reached. It must give the same result to the paisa: the amount
/// printed on an offline receipt is the amount later recorded on the server.
///
/// Order of calculation: items -> discount (spread over items) -> service /
/// packaging / delivery charges -> GST per rate -> round-off.
library;

/// JavaScript's Math.round: halves go up, also for negative numbers.
int _jsRound(double value) => (value + 0.5).floor();

double round2(num n) => _jsRound((n.toDouble() + 2.220446049250313e-16) * 100) / 100;

double _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

double _rateFor(Map<String, dynamic> settings, Object? taxRate) {
  if (settings['taxEnabled'] != true) return 0;
  if (taxRate != null && taxRate != '') {
    final own = taxRate is num ? taxRate.toDouble() : double.tryParse('$taxRate');
    if (own != null && own.isFinite) return own;
  }
  return _num(settings['taxPercent']);
}

bool _appliesTo(Object? list, String orderType) => list is List && list.contains(orderType);

/// [lines]: name, price, quantity, taxRate, quickItem and whatever else
/// should stay on the line. [adjust]: discountType, discountValue,
/// discountReason, serviceCharge, packagingCharge, deliveryCharge,
/// complimentary, complimentaryReason.
Map<String, dynamic> computeLocalBill({
  required List<Map<String, dynamic>> lines,
  required Map<String, dynamic> settings,
  String orderType = 'takeaway',
  Map<String, dynamic> adjust = const {},
}) {
  final type = const ['dine_in', 'takeaway', 'delivery'].contains(orderType) ? orderType : 'takeaway';
  final inclusive = settings['taxEnabled'] == true && settings['taxInclusive'] == true;

  final items = lines.map((line) {
    final quantity = _num(line['quantity']);
    final price = round2(_num(line['price']));
    final taxRate = line['quickItem'] != null ? _rateFor(settings, null) : _rateFor(settings, line['taxRate']);
    return <String, dynamic>{...line, 'price': price, 'quantity': quantity.toInt(), 'taxRate': taxRate, 'total': round2(price * quantity)};
  }).toList();
  final subtotal = round2(items.fold<double>(0, (s, i) => s + (i['total'] as double)));

  // Discount (complimentary = everything free).
  final complimentary = adjust['complimentary'] == true;
  var discountType = adjust['discountType'] == 'percent' ? 'percent' : 'flat';
  var discountValue = _num(adjust['discountValue'] ?? adjust['discount'] ?? 0);
  if (discountValue < 0) discountValue = 0;
  if (discountType == 'percent' && discountValue > 100) discountValue = 100;
  var discount = discountType == 'percent' ? round2(subtotal * discountValue / 100) : round2(discountValue);
  if (complimentary) {
    discountType = 'percent';
    discountValue = 100;
    discount = subtotal;
  }
  if (discount > subtotal) discount = subtotal;
  String reasonOf(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  final discountReason = complimentary
      ? reasonOf(adjust['complimentaryReason'] ?? adjust['discountReason'] ?? 'Complimentary')
      : reasonOf(adjust['discountReason']);

  // Spread the discount over items by value so each GST rate gets its share.
  var remaining = discount;
  final itemDiscounts = <double>[];
  for (var i = 0; i < items.length; i++) {
    final total = items[i]['total'] as double;
    final share = i == items.length - 1 ? remaining : (subtotal > 0 ? round2(discount * total / subtotal) : 0.0);
    final applied = share < total ? share : total;
    itemDiscounts.add(applied);
    remaining = round2(remaining - applied);
  }

  // Charges (none on a complimentary bill).
  final afterDiscount = round2(subtotal - discount);
  final scPercent = _num(settings['serviceChargePercent']);
  final wantsService = adjust['serviceCharge'] != null
      ? adjust['serviceCharge'] == true
      : _appliesTo(settings['serviceChargeOn'], type);
  final serviceCharge = !complimentary && wantsService && scPercent > 0 ? round2(afterDiscount * scPercent / 100) : 0.0;
  final packagingDefault = _appliesTo(settings['packagingChargeOn'], type) ? _num(settings['packagingCharge']) : 0.0;
  final packagingValue = _num(adjust['packagingCharge'] ?? packagingDefault);
  final packagingCharge = complimentary || packagingValue < 0 ? 0.0 : round2(packagingValue);
  final deliveryDefault = type == 'delivery' ? _num(settings['deliveryCharge']) : 0.0;
  final deliveryValue = _num(adjust['deliveryCharge'] ?? deliveryDefault);
  final deliveryCharge = complimentary || type != 'delivery' || deliveryValue < 0 ? 0.0 : round2(deliveryValue);
  final charges = round2(serviceCharge + packagingCharge + deliveryCharge);

  // GST per rate, in the order the rates first appear.
  final byRate = <double, Map<String, double>>{};
  void addTax(double rate, double taxable, double tax) {
    final row = byRate.putIfAbsent(rate, () => {'taxable': 0, 'tax': 0});
    row['taxable'] = round2(row['taxable']! + taxable);
    row['tax'] = round2(row['tax']! + tax);
  }

  for (var i = 0; i < items.length; i++) {
    final net = round2((items[i]['total'] as double) - itemDiscounts[i]);
    final rate = items[i]['taxRate'] as double;
    if (rate > 0) {
      final taxable = inclusive ? round2(net / (1 + rate / 100)) : net;
      final tax = inclusive ? round2(net - taxable) : round2(taxable * rate / 100);
      addTax(rate, taxable, tax);
    } else {
      addTax(0, net, 0);
    }
  }
  final chargeRate = _rateFor(settings, null);
  if (charges > 0) addTax(chargeRate, charges, round2(charges * chargeRate / 100));

  final igst = settings['gstType'] == 'igst';
  final rates = byRate.keys.where((rate) => rate > 0 && byRate[rate]!['tax']! > 0).toList()..sort();
  final taxes = rates.map((rate) {
    final row = byRate[rate]!;
    if (igst) {
      return <String, dynamic>{'rate': rate, 'taxable': row['taxable'], 'cgst': 0.0, 'sgst': 0.0, 'igst': row['tax'], 'tax': row['tax']};
    }
    final half = round2(row['tax']! / 2);
    return <String, dynamic>{'rate': rate, 'taxable': row['taxable'], 'cgst': half, 'sgst': half, 'igst': 0.0, 'tax': round2(half * 2)};
  }).toList();
  final tax = round2(taxes.fold<double>(0, (s, t) => s + (t['tax'] as double)));
  final taxableAmount = round2(byRate.values.fold<double>(0, (s, r) => s + r['taxable']!));

  // Inclusive prices already contain their GST; only charges add tax on top.
  final beforeRound = inclusive
      ? round2(afterDiscount + charges + round2(charges * chargeRate / 100))
      : round2(taxableAmount + tax);
  final grandTotal = settings['roundOff'] == false ? beforeRound : _jsRound(beforeRound).toDouble();
  final roundOff = round2(grandTotal - beforeRound);

  return {
    'orderItems': items,
    'subtotal': subtotal,
    'discount': discount,
    'discountType': discountType,
    'discountValue': discountValue,
    'discountReason': discountReason,
    'complimentary': complimentary,
    'serviceCharge': serviceCharge,
    'serviceChargePercent': serviceCharge > 0 ? scPercent : 0.0,
    'packagingCharge': packagingCharge,
    'deliveryCharge': deliveryCharge,
    'taxableAmount': taxableAmount,
    'taxes': taxes,
    'tax': tax,
    'taxInclusive': inclusive,
    'roundOff': roundOff,
    'grandTotal': grandTotal,
  };
}
