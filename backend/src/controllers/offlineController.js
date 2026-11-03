const {
  Order,
  Product,
  Customer,
  Table,
  Counter,
  CreditTransaction,
  InventoryTransaction,
  BusinessSettings,
  AuditLog,
} = require('../models');
const { startSession } = require('../tenancy/context');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { computeBill, billFields, financialYear } = require('../services/billing');

function round2(n) {
  return Math.round((Number(n) + Number.EPSILON) * 100) / 100;
}

const money = (v) => round2(Math.max(0, Number(v) || 0));

// Bills older than this cannot be real offline work; they get today's date.
const MAX_OFFLINE_AGE_MS = 30 * 24 * 60 * 60 * 1000;

function offlineDate(value) {
  const date = new Date(value);
  const now = Date.now();
  if (Number.isNaN(date.getTime()) || date.getTime() > now + 5 * 60 * 1000 || date.getTime() < now - MAX_OFFLINE_AGE_MS) {
    return new Date();
  }
  return date;
}

function breakdownOf(body, grandTotal) {
  const breakdown = { cash: 0, upi: 0, card: 0, online: 0, credit: 0 };
  switch (body.paymentMethod) {
    case 'CASH': breakdown.cash = grandTotal; break;
    case 'UPI': breakdown.upi = grandTotal; break;
    case 'CARD': breakdown.card = grandTotal; break;
    case 'ONLINE': breakdown.online = grandTotal; break;
    case 'CREDIT': breakdown.credit = grandTotal; break;
    case 'MIXED':
      breakdown.cash = money(body.cashPortion);
      breakdown.upi = money(body.upiPortion);
      breakdown.card = money(body.cardPortion);
      breakdown.credit = money(body.creditPortion);
      break;
    default: break;
  }
  return breakdown;
}

// POST /api/orders/offline-sync
//
// A bill made while the device had no internet. The customer has already
// paid and may hold a printed receipt, so this records what actually
// happened: the prices, GST settings and time from the device, and stock may
// go below zero. Nothing here can refuse a real sale because the menu or the
// stock moved on in the meantime. Sending the same bill again is harmless.
const syncOfflineOrder = asyncHandler(async (req, res) => {
  const body = req.body || {};
  const clientRequestId = typeof body.clientRequestId === 'string' ? body.clientRequestId.trim().slice(0, 100) : '';
  if (!clientRequestId) throw new ApiError(400, 'clientRequestId is required.');
  if (!Array.isArray(body.items)) throw new ApiError(400, 'items are required.');

  const open = body.status === 'open';
  if (!open && body.items.length === 0) throw new ApiError(400, 'A bill needs at least one item.');

  const existing = await Order.findOne({ clientRequestId });
  if (existing) return res.json({ success: true, data: { order: existing, duplicate: true } });

  const lines = body.items.map((line) => {
    const quantity = Number(line.quantity);
    const name = String(line.name || '').trim();
    if (!name || !Number.isFinite(quantity) || quantity <= 0) throw new ApiError(400, 'Invalid bill line.');
    return {
      product: /^[0-9a-f]{24}$/i.test(String(line.productId || '')) ? line.productId : undefined,
      quickItem: line.quick ? { name, price: money(line.price) } : undefined,
      name,
      price: money(line.price),
      quantity,
      taxRate: line.taxRate,
      note: typeof line.note === 'string' && line.note.trim() ? line.note.trim().slice(0, 120) : undefined,
      kotSentQuantity: Number(line.kotSentQuantity) || 0,
    };
  });

  const settings = body.settings && typeof body.settings === 'object'
    ? body.settings
    : await BusinessSettings.getSettings();
  const orderType = ['dine_in', 'takeaway', 'delivery'].includes(body.orderType) ? body.orderType : 'takeaway';
  const bill = computeBill({
    lines,
    settings,
    orderType,
    adjust: {
      discountType: body.discountType,
      discountValue: body.discountValue,
      discountReason: body.discountReason,
      serviceCharge: body.serviceCharge,
      packagingCharge: body.packagingCharge,
      deliveryCharge: body.deliveryCharge,
      complimentary: body.paymentMethod === 'COMPLIMENTARY',
    },
  });

  // The amount on the customer's receipt is the amount that was charged.
  const charged = Number(body.grandTotal);
  const mismatch = !open && Number.isFinite(charged) && Math.abs(charged - bill.grandTotal) > 0.01;
  if (mismatch) {
    bill.roundOff = round2(bill.roundOff + charged - bill.grandTotal);
    bill.grandTotal = round2(charged);
  }

  const createdAt = offlineDate(body.createdAt);
  const session = await startSession();
  let saved;
  try {
    await session.withTransaction(async () => {
      const orderNumber = await Counter.getNextSequence('orderNumber', session);
      let invoiceNumber;
      if (!open) {
        const current = await BusinessSettings.getSettings(session);
        const fy = financialYear(createdAt);
        const seq = await Counter.getNextSequence(`invoice:${fy}`, session);
        const prefix = String(current.invoicePrefix || '').trim();
        invoiceNumber = `${prefix ? `${prefix}/` : ''}${fy}/${String(seq).padStart(4, '0')}`;
      }

      const table = body.tableId && /^[0-9a-f]{24}$/i.test(String(body.tableId))
        ? await Table.findById(body.tableId).session(session)
        : null;
      const customer = body.customerId && /^[0-9a-f]{24}$/i.test(String(body.customerId))
        ? await Customer.findById(body.customerId).session(session)
        : null;

      const breakdown = open ? { cash: 0, upi: 0, card: 0, online: 0, credit: 0 } : breakdownOf(body, bill.grandTotal);
      const [order] = await Order.create([{
        orderNumber,
        invoiceNumber,
        clientRequestId,
        offline: true,
        offlineRef: typeof body.offlineRef === 'string' ? body.offlineRef.trim().slice(0, 40) : undefined,
        items: bill.orderItems,
        ...billFields(bill),
        orderType,
        orderSource: 'pos',
        table: table?._id,
        tableCustomerLabel: body.tableCustomerLabel || undefined,
        deliveryInfo: orderType === 'delivery' ? body.deliveryInfo : undefined,
        paymentMethod: open ? undefined : body.paymentMethod,
        paymentStatus: open ? 'pending' : 'paid',
        paymentBreakdown: breakdown,
        upiReference: open ? undefined : (String(body.upiReference || '').trim() || undefined),
        amountReceived: open ? undefined : body.amountReceived,
        changeReturned: open || body.amountReceived === undefined || body.amountReceived === null
          ? 0
          : money(Number(body.amountReceived) - bill.grandTotal),
        onlinePlatform: body.paymentMethod === 'ONLINE' ? body.onlinePlatform : undefined,
        onlineOrderRef: body.paymentMethod === 'ONLINE' ? body.onlineOrderRef : undefined,
        cardReference: ['CARD', 'MIXED'].includes(body.paymentMethod) ? body.cardReference : undefined,
        customer: customer?._id,
        notes: body.notes || undefined,
        staff: req.user._id,
        status: open ? 'open' : 'completed',
        kitchenStatus: 'served',
        createdAt,
      }], { session });

      if (!open) {
        for (const line of bill.orderItems) {
          if (!line.product) continue;
          const product = await Product.findOneAndUpdate(
            { _id: line.product, trackInventory: true },
            { $inc: { stock: -line.quantity } },
            { new: true, session }
          );
          if (product) {
            await InventoryTransaction.create([{
              product: product._id,
              type: 'SALE',
              quantity: -line.quantity,
              stockAfter: product.stock,
              reason: `Sold offline in bill #${order.orderNumber}`,
              order: order._id,
              recordedBy: req.user._id,
            }], { session });
          }
        }
        if (customer) {
          customer.totalPurchases = round2(customer.totalPurchases + bill.grandTotal);
          if (breakdown.credit > 0) customer.outstandingBalance = round2(customer.outstandingBalance + breakdown.credit);
          await customer.save({ session });
          if (breakdown.credit > 0) {
            await CreditTransaction.create([{
              customer: customer._id,
              type: 'DEBIT',
              amount: breakdown.credit,
              method: 'ORDER',
              order: order._id,
              balanceAfter: customer.outstandingBalance,
              note: `Bill #${order.orderNumber} (offline)`,
              recordedBy: req.user._id,
            }], { session });
          }
        }
      }
      saved = order;
    });
  } catch (err) {
    if (err.code === 11000 && err.keyPattern?.clientRequestId) {
      const order = await Order.findOne({ clientRequestId });
      if (order) return res.json({ success: true, data: { order, duplicate: true } });
    }
    throw err;
  } finally {
    await session.endSession();
  }

  try {
    await AuditLog.create({
      actor: req.user._id,
      action: open ? 'OFFLINE_ORDER_SYNCED' : 'OFFLINE_BILL_SYNCED',
      entityType: 'Order',
      entityId: saved._id,
      orderNumber: saved.orderNumber,
      details: { offlineRef: saved.offlineRef, createdAt, grandTotal: saved.grandTotal, totalAdjusted: mismatch },
      ip: req.ip,
    });
  } catch (_) {
    // Audit logging must never break a sale.
  }

  res.status(201).json({ success: true, data: { order: saved } });
});

module.exports = { syncOfflineOrder };
