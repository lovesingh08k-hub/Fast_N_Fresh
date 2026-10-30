// Bill calculation shared by every way a bill is made (counter bill, open
// table/counter order, checkout, customer QR order, quote preview), so the
// amount shown while ordering is exactly what the final bill charges.
//
// Order of calculation (Indian restaurant billing):
//   items  ->  discount (spread over items)  ->  service / packaging /
//   delivery charges  ->  GST per rate (CGST+SGST or IGST)  ->  round-off.
// Item prices may include GST (settings.taxInclusive) or not. Charges are
// always before tax and taxed at the default GST rate.

function round2(n) {
  return Math.round((Number(n) + Number.EPSILON) * 100) / 100;
}

const ORDER_TYPES = ['dine_in', 'takeaway', 'delivery'];

/** GST rate of an item: its own rate, else the default; 0 when GST is off. */
function rateFor(settings, taxRate) {
  if (!settings.taxEnabled) return 0;
  const own = Number(taxRate);
  if (taxRate !== null && taxRate !== undefined && taxRate !== '' && Number.isFinite(own)) return own;
  return Number(settings.taxPercent) || 0;
}

/** Whether a charge configured for some order types applies to this one. */
function appliesTo(list, orderType) {
  return Array.isArray(list) && list.includes(orderType);
}

/**
 * @param {object} p
 * @param {Array<{name, price, quantity, taxRate?, product?, quickItem?, note?, kotSentQuantity?}>} p.lines
 *        priced lines (price = unit selling price as stored on the menu)
 * @param {object} p.settings BusinessSettings
 * @param {string} p.orderType dine_in | takeaway | delivery
 * @param {object} [p.adjust]
 *   discountType 'flat'|'percent', discountValue, discountReason,
 *   serviceCharge (bool; default from settings for the order type),
 *   packagingCharge (number; default from settings), deliveryCharge (number),
 *   complimentary (bool), complimentaryReason
 */
function computeBill({ lines, settings, orderType = 'takeaway', adjust = {} }) {
  const type = ORDER_TYPES.includes(orderType) ? orderType : 'takeaway';
  const inclusive = Boolean(settings.taxEnabled && settings.taxInclusive);

  const items = lines.map((l) => {
    const quantity = Number(l.quantity);
    const price = round2(l.price);
    const taxRate = l.quickItem ? rateFor(settings, null) : rateFor(settings, l.taxRate);
    return { ...l, price, quantity, taxRate, total: round2(price * quantity) };
  });
  const subtotal = round2(items.reduce((s, i) => s + i.total, 0));

  // ---- Discount (complimentary = everything free).
  const complimentary = Boolean(adjust.complimentary);
  let discountType = adjust.discountType === 'percent' ? 'percent' : 'flat';
  let discountValue = Math.max(0, Number(adjust.discountValue ?? adjust.discount ?? 0) || 0);
  if (discountType === 'percent') discountValue = Math.min(discountValue, 100);
  let discount = discountType === 'percent' ? round2((subtotal * discountValue) / 100) : round2(discountValue);
  if (complimentary) {
    discountType = 'percent';
    discountValue = 100;
    discount = subtotal;
  }
  discount = Math.min(discount, subtotal);
  const discountReason = complimentary
    ? String(adjust.complimentaryReason || adjust.discountReason || 'Complimentary').trim().slice(0, 120)
    : String(adjust.discountReason || '').trim().slice(0, 120);

  // Spread the discount over items by value so each GST rate gets its share.
  let remaining = discount;
  items.forEach((item, index) => {
    const share = index === items.length - 1
      ? remaining
      : subtotal > 0 ? round2((discount * item.total) / subtotal) : 0;
    item.discount = Math.min(share, item.total);
    remaining = round2(remaining - item.discount);
  });

  // ---- Charges (none on a complimentary bill).
  const afterDiscount = round2(subtotal - discount);
  const scPercent = Number(settings.serviceChargePercent) || 0;
  const wantsService = adjust.serviceCharge !== undefined
    ? Boolean(adjust.serviceCharge)
    : appliesTo(settings.serviceChargeOn, type);
  const serviceCharge = !complimentary && wantsService && scPercent > 0
    ? round2((afterDiscount * scPercent) / 100)
    : 0;
  const packagingDefault = appliesTo(settings.packagingChargeOn, type) ? Number(settings.packagingCharge) || 0 : 0;
  const packagingCharge = complimentary ? 0 : round2(Math.max(0, Number(adjust.packagingCharge ?? packagingDefault) || 0));
  const deliveryDefault = type === 'delivery' ? Number(settings.deliveryCharge) || 0 : 0;
  const deliveryCharge = complimentary || type !== 'delivery'
    ? 0
    : round2(Math.max(0, Number(adjust.deliveryCharge ?? deliveryDefault) || 0));
  const charges = round2(serviceCharge + packagingCharge + deliveryCharge);

  // ---- GST per rate.
  const byRate = new Map();
  const addTax = (rate, taxable, tax) => {
    const row = byRate.get(rate) || { rate, taxable: 0, tax: 0 };
    row.taxable = round2(row.taxable + taxable);
    row.tax = round2(row.tax + tax);
    byRate.set(rate, row);
  };
  for (const item of items) {
    const net = round2(item.total - item.discount);
    if (item.taxRate > 0) {
      const taxable = inclusive ? round2(net / (1 + item.taxRate / 100)) : net;
      const tax = inclusive ? round2(net - taxable) : round2((taxable * item.taxRate) / 100);
      addTax(item.taxRate, taxable, tax);
    } else {
      addTax(0, net, 0);
    }
  }
  const chargeRate = rateFor(settings, null);
  if (charges > 0) addTax(chargeRate, charges, round2((charges * chargeRate) / 100));

  const igst = settings.gstType === 'igst';
  const taxes = [...byRate.values()]
    .filter((row) => row.rate > 0 && row.tax > 0)
    .sort((a, b) => a.rate - b.rate)
    .map((row) => {
      const half = round2(row.tax / 2);
      return igst
        ? { rate: row.rate, taxable: row.taxable, cgst: 0, sgst: 0, igst: row.tax, tax: row.tax }
        : { rate: row.rate, taxable: row.taxable, cgst: half, sgst: round2(row.tax - half), igst: 0, tax: row.tax };
    });
  const tax = round2(taxes.reduce((s, t) => s + t.tax, 0));
  const taxableAmount = round2([...byRate.values()].reduce((s, r) => s + r.taxable, 0));

  // Inclusive prices already contain their GST; only charges add tax on top.
  const beforeRound = inclusive
    ? round2(afterDiscount + charges + round2((charges * chargeRate) / 100))
    : round2(taxableAmount + tax);
  const grandTotal = settings.roundOff === false ? beforeRound : Math.round(beforeRound);
  const roundOff = round2(grandTotal - beforeRound);

  return {
    orderItems: items.map(({ discount: _d, ...item }) => item),
    subtotal,
    discount,
    discountType,
    discountValue,
    discountReason,
    complimentary,
    serviceCharge,
    serviceChargePercent: serviceCharge > 0 ? scPercent : 0,
    packagingCharge,
    deliveryCharge,
    taxableAmount,
    taxes,
    tax,
    taxInclusive: inclusive,
    roundOff,
    grandTotal,
  };
}

/** Order fields to store from a computed bill. */
function billFields(bill) {
  return {
    subtotal: bill.subtotal,
    discount: bill.discount,
    discountType: bill.discountType,
    discountValue: bill.discountValue,
    discountReason: bill.discountReason || undefined,
    complimentary: bill.complimentary,
    serviceCharge: bill.serviceCharge,
    serviceChargePercent: bill.serviceChargePercent,
    packagingCharge: bill.packagingCharge,
    deliveryCharge: bill.deliveryCharge,
    taxableAmount: bill.taxableAmount,
    taxes: bill.taxes,
    tax: bill.tax,
    taxInclusive: bill.taxInclusive,
    roundOff: bill.roundOff,
    grandTotal: bill.grandTotal,
  };
}

/** The bill adjustments sent by the app (body), or those already on an order. */
function adjustFrom(body = {}, order = null) {
  const pick = (key, fallback) => (body[key] !== undefined ? body[key] : fallback);
  return {
    discountType: pick('discountType', order?.discountType),
    // Older apps send only `discount` (a flat amount).
    discountValue: pick(
      'discountValue',
      body.discount !== undefined && body.discountType === undefined
        ? body.discount
        // Orders from before discount types only have the flat amount.
        : order ? order.discountValue || (order.discountType !== 'percent' ? order.discount : 0) : undefined
    ),
    discountReason: pick('discountReason', order?.discountReason),
    serviceCharge: pick('serviceCharge', order?.serviceChargeEnabled),
    packagingCharge: pick('packagingCharge', order?.packagingChargeOverride),
    deliveryCharge: pick('deliveryCharge', order?.deliveryChargeOverride),
    complimentary: pick('paymentMethod', null) === 'COMPLIMENTARY' || pick('complimentary', false),
    complimentaryReason: pick('complimentaryReason', undefined),
  };
}

/** Indian financial year label for a date, e.g. 2026-10-29 -> "26-27". */
function financialYear(date = new Date()) {
  const ist = new Date(date.getTime() + 5.5 * 3600 * 1000);
  const year = ist.getUTCFullYear();
  const start = ist.getUTCMonth() >= 3 ? year : year - 1; // FY starts 1 April
  return `${String(start).slice(-2)}-${String(start + 1).slice(-2)}`;
}

module.exports = { computeBill, billFields, adjustFrom, financialYear, round2, rateFor };
