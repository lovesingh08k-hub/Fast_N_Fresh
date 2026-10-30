const mongoose = require('mongoose');
const { startSession } = require('../tenancy/context');
const {
  Order,
  User,
  Product,
  Customer,
  Table,
  Counter,
  CreditTransaction,
  InventoryTransaction,
  BusinessSettings,
  AuditLog,
  RefundTransaction,
  DayClose,
} = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { parseClientDate } = require('../utils/dateRanges');
const { computeBill, billFields, adjustFrom, financialYear } = require('../services/billing');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function normalizeRequestId(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  if (!id) return undefined;
  if (id.length > 100 || !/^[A-Za-z0-9._:-]+$/.test(id)) {
    throw new ApiError(400, 'Invalid client request id.');
  }
  return id;
}

async function assertBusinessDayOpen() {
  const businessDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
  const { DayClose } = require('../models');
  const day = await DayClose.findOne({ businessDate });
  if (day?.status === 'closed') throw new ApiError(409, 'Business day is closed. Reopen the day before taking new orders.');
}

async function audit(req, action, order, details = {}) {
  try {
    await AuditLog.create({ actor: req.user?._id, action, entityType: 'Order', entityId: order?._id, orderNumber: order?.orderNumber, details, ip: req.ip });
  } catch (_) {
    // Audit logging must never break a sale.
  }
}

// Shared pricing and validation logic used by direct bills and QR/open-order
// checkout. Prices always come from the menu (never the client); the bill
// itself is calculated by services/billing.
const PAYMENT_METHODS = ['CASH', 'UPI', 'CARD', 'ONLINE', 'CREDIT', 'MIXED', 'COMPLIMENTARY'];

/**
 * Validates cart lines against the menu and returns priced lines
 * (name, price, taxRate from the product) ready for computeBill.
 */
async function priceLines(items, { session, checkStock = true } = {}) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new ApiError(400, 'Cart is empty. Add at least one item.');
  }

  const productIds = items
    .filter((i) => !(i.quickItem && String(i.quickItem.name || '').trim()))
    .map((i) => i.productId || i.product)
    .filter(Boolean);

  const query = Product.find({ _id: { $in: productIds }, isDeleted: false });
  if (session) query.session(session);
  const products = await query;
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const lines = [];
  for (const line of items) {
    const quantity = Number(line.quantity);
    const note = typeof line.note === 'string' && line.note.trim() ? line.note.trim().slice(0, 120) : undefined;
    const quick = line.quickItem;

    if (quick && String(quick.name || '').trim()) {
      const quickName = String(quick.name).trim();
      const quickPrice = Number(quick.price);
      if (!quickName || !Number.isFinite(quickPrice) || quickPrice < 0) {
        throw new ApiError(400, 'Invalid Quick Item name or price.');
      }
      if (!Number.isFinite(quantity) || quantity < 1) {
        throw new ApiError(400, `Invalid quantity for ${quickName}.`);
      }
      lines.push({ name: quickName, price: quickPrice, quantity, note, quickItem: { name: quickName, price: quickPrice } });
      continue;
    }

    const product = productMap.get(String(line.productId || line.product));
    if (!product) throw new ApiError(400, 'Product not found or unavailable.');
    if (product.status !== 'available') throw new ApiError(400, `${product.name} is currently unavailable.`);
    if (!Number.isFinite(quantity) || quantity < 1) throw new ApiError(400, `Invalid quantity for ${product.name}.`);
    if (checkStock && product.trackInventory && product.stock < quantity) {
      throw new ApiError(400, `Insufficient stock for ${product.name}. Available: ${product.stock}.`);
    }
    lines.push({
      product: product._id,
      name: product.name,
      price: product.sellingPrice,
      quantity,
      taxRate: product.taxRate,
      note,
      ...(line.kotSentQuantity !== undefined ? { kotSentQuantity: line.kotSentQuantity } : {}),
    });
  }
  return { lines, productMap };
}

async function priceAndValidate({
  items,
  orderType,
  adjust = {},
  paymentMethod,
  amountReceived,
  customerId,
  cashPortion,
  upiPortion,
  cardPortion,
  creditPortion,
  onlinePlatform,
  session,
}) {
  if (!PAYMENT_METHODS.includes(paymentMethod)) {
    throw new ApiError(400, 'A valid payment method is required.');
  }

  const { lines, productMap } = await priceLines(items, { session });
  const settings = await BusinessSettings.getSettings(session);
  const bill = computeBill({
    lines,
    settings,
    orderType,
    adjust: { ...adjust, complimentary: paymentMethod === 'COMPLIMENTARY' || adjust.complimentary },
  });
  const { grandTotal } = bill;

  const paymentBreakdown = { cash: 0, upi: 0, card: 0, online: 0, credit: 0 };
  switch (paymentMethod) {
    case 'CASH': paymentBreakdown.cash = grandTotal; break;
    case 'UPI': paymentBreakdown.upi = grandTotal; break;
    case 'CARD': paymentBreakdown.card = grandTotal; break;
    case 'ONLINE':
      if (!String(onlinePlatform || '').trim()) {
        throw new ApiError(400, 'Choose the delivery app (e.g. Swiggy / Zomato) for an online order.');
      }
      paymentBreakdown.online = grandTotal;
      break;
    case 'CREDIT': paymentBreakdown.credit = grandTotal; break;
    case 'COMPLIMENTARY':
      if (grandTotal !== 0) throw new ApiError(400, 'A complimentary bill must total zero.');
      break;
    case 'MIXED': {
      Object.assign(paymentBreakdown, {
        cash: round2(Number(cashPortion) || 0),
        upi: round2(Number(upiPortion) || 0),
        card: round2(Number(cardPortion) || 0),
        credit: round2(Number(creditPortion) || 0),
      });
      if (Object.values(paymentBreakdown).some((v) => !Number.isFinite(v) || v < 0)) {
        throw new ApiError(400, 'Mixed payment portions must be zero or positive amounts.');
      }
      const sum = round2(paymentBreakdown.cash + paymentBreakdown.upi + paymentBreakdown.card + paymentBreakdown.credit);
      if (sum !== grandTotal) {
        throw new ApiError(400, `Mixed payment split (Rs ${sum}) does not equal grand total (Rs ${grandTotal}).`);
      }
      break;
    }
    default:
      break;
  }

  let changeReturned = 0;
  if (paymentMethod === 'CASH' && amountReceived !== undefined && amountReceived !== null && amountReceived !== '') {
    const received = Number(amountReceived);
    if (!Number.isFinite(received)) throw new ApiError(400, 'Amount received must be a valid number.');
    if (received < grandTotal) throw new ApiError(400, 'Amount received is less than the grand total.');
    changeReturned = round2(received - grandTotal);
  }

  let customer = null;
  if (customerId) {
    customer = await Customer.findById(customerId).session(session);
    if (!customer) throw new ApiError(404, 'Selected customer not found.');
  }
  if (paymentBreakdown.credit > 0 && !customer) {
    throw new ApiError(400, 'A customer must be selected for the credit portion of this bill.');
  }

  return {
    ...bill,
    bill,
    productMap,
    safeDiscount: bill.discount,
    paymentBreakdown,
    changeReturned,
    customer,
  };
}

/** Next invoice number of this outlet for the current financial year. */
async function nextInvoiceNumber(session) {
  const settings = await BusinessSettings.getSettings(session);
  const fy = financialYear();
  const seq = await Counter.getNextSequence(`invoice:${fy}`, session);
  const prefix = String(settings.invoicePrefix || '').trim();
  return `${prefix ? `${prefix}/` : ''}${fy}/${String(seq).padStart(4, '0')}`;
}

/** Payment details stored on the order, from the request body. */
function paymentExtras(body) {
  const clean = (v) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 80) : undefined);
  return {
    onlinePlatform: body.paymentMethod === 'ONLINE' ? clean(body.onlinePlatform) : undefined,
    onlineOrderRef: body.paymentMethod === 'ONLINE' ? clean(body.onlineOrderRef) : undefined,
    cardReference: ['CARD', 'MIXED'].includes(body.paymentMethod) ? clean(body.cardReference) : undefined,
  };
}

// Applies inventory deductions and customer credit effects.
async function applyInventoryAndCredit({
  session,
  req,
  order,
  orderItems,
  productMap,
  customer,
  paymentBreakdown,
  grandTotal,
}) {
  for (const line of orderItems) {
    const product = line.product ? productMap.get(line.product.toString()) : null;
    if (!product || !product.trackInventory) continue;
    const updated = await Product.findOneAndUpdate({_id:product._id,stock:{$gte:line.quantity}},{$inc:{stock:-line.quantity}},{new:true,session});
    if (!updated) throw new ApiError(400, `Insufficient stock for ${product.name}.`);
    await InventoryTransaction.create([{product:product._id,type:'SALE',quantity:-line.quantity,stockAfter:updated.stock,reason:`Sold in bill #${order.orderNumber}`,order:order._id,recordedBy:req.user._id}],{session});
  }

  if (
    customer &&
    paymentBreakdown.credit > 0
  ) {
    customer.totalPurchases = round2(
      customer.totalPurchases + grandTotal
    );

    customer.outstandingBalance = round2(
      customer.outstandingBalance +
        paymentBreakdown.credit
    );

    await customer.save({ session });

    await CreditTransaction.create(
      [
        {
          customer: customer._id,
          type: 'DEBIT',
          amount: paymentBreakdown.credit,
          method: 'ORDER',
          order: order._id,
          balanceAfter: customer.outstandingBalance,
          note: `Bill #${order.orderNumber}`,
          recordedBy: req.user._id,
        },
      ],
      { session }
    );
  } else if (customer) {
    customer.totalPurchases = round2(
      customer.totalPurchases + grandTotal
    );

    await customer.save({ session });
  }
}

// ---------------------------------------------------------------------------
// KITCHEN / KOT HELPERS
// ---------------------------------------------------------------------------
function orderLineKey(line) {
  if (line.product) return `product:${line.product.toString()}`;
  const quick = line.quickItem;
  return `quick:${String(quick?.name || line.name || '').trim().toLowerCase()}:${Number(quick?.price ?? line.price ?? 0)}`;
}

function appendKotFromUnsents(order, userId) {
  const deltaItems = [];
  for (const line of order.items) {
    const sent = Number(line.kotSentQuantity || 0);
    const delta = Number(line.quantity || 0) - sent;
    if (delta > 0) {
      deltaItems.push({
        product: line.product,
        name: line.name,
        quantity: delta,
        note: line.note,
      });
    }
  }

  if (!deltaItems.length) return null;

  const kotNumber = order.kots.length + 1;
  const kot = {
    kotNumber,
    items: deltaItems,
    status: 'new',
    sentBy: userId,
    createdAt: new Date(),
  };
  order.kots.push(kot);

  const deltaByKey = new Map(deltaItems.map((item) => [orderLineKey(item), item.quantity]));
  for (const line of order.items) {
    const key = orderLineKey(line);
    const sent = Number(line.kotSentQuantity || 0);
    const delta = deltaByKey.get(key) || 0;
    if (delta > 0) line.kotSentQuantity = sent + delta;
  }

  // If the kitchen was already finished, adding another KOT reopens it.
  if (order.kitchenStatus === 'served') order.kitchenStatus = 'new';
  return kot;
}

function preserveKotSentQuantities(previousItems, nextItems) {
  const sentByKey = new Map();
  for (const line of previousItems || []) {
    sentByKey.set(orderLineKey(line), Number(line.kotSentQuantity || 0));
  }
  const nextKeys = new Set();
  for (const line of nextItems) {
    const key = orderLineKey(line);
    nextKeys.add(key);
    const previousSent = sentByKey.get(key) || 0;
    if (previousSent > line.quantity) {
      throw new ApiError(409, `Cannot reduce ${line.name} below the quantity already sent to kitchen.`);
    }
    line.kotSentQuantity = previousSent;
  }
  // Removing a line entirely is the same as reducing it to zero.
  for (const line of previousItems || []) {
    if (Number(line.kotSentQuantity || 0) > 0 && !nextKeys.has(orderLineKey(line))) {
      throw new ApiError(409, `Cannot remove ${line.name}; it has already been sent to kitchen.`);
    }
  }
}

// POST /api/orders
// Creates a completed POS order.
const createOrder = asyncHandler(async (req, res) => {
  const {
    items,
    discount = 0,
    paymentMethod,
    amountReceived,
    upiReference,
    customerId,
    notes,
    cashPortion,
    upiPortion,
    creditPortion,
    orderType,
    tableId,
    tableCustomerLabel,
    deliveryInfo,
    clientRequestId,
  } = req.body;

  await assertBusinessDayOpen();

  const normalizedClientRequestId = normalizeRequestId(clientRequestId);

  // Idempotency: if the app is retrying a checkout it already sent (lost
  // response after a Render cold-start timeout, a double-tap that slipped
  // past the frontend's submit-lock, etc.), return the original order
  // instead of creating a second bill/payment.
  if (normalizedClientRequestId) {
    const existing = await Order.findOne({ clientRequestId: normalizedClientRequestId })
      .populate('customer', 'name phone')
      .populate('staff', 'name role')
      .populate('table', 'name')
      .populate('items.product', 'name imageUrl');

    if (existing) {
      return res.status(200).json({
        success: true,
        message: 'Bill created successfully.',
        data: { order: existing, customer: existing.customer || null },
      });
    }
  }

  const normalizedUpiReference = typeof upiReference === 'string' ? upiReference.trim() : '';
  if (paymentMethod === 'UPI' && !normalizedUpiReference) {
    throw new ApiError(400, 'UPI reference / UTR is required for UPI payments.');
  }
  if (normalizedUpiReference.length > 100) {
    throw new ApiError(400, 'UPI reference / UTR is too long.');
  }
  if (normalizedUpiReference) {
    const existingPayment = await Order.findOne({ upiReference: normalizedUpiReference, paymentStatus: 'paid' }).select('_id orderNumber');
    if (existingPayment) throw new ApiError(409, `This UPI reference is already used on bill #${existingPayment.orderNumber}.`);
  }
  if (paymentMethod === 'MIXED' && Number(upiPortion) > 0 && (!upiReference || !String(upiReference).trim())) {
    throw new ApiError(400, 'UPI reference / UTR is required when Mixed payment includes UPI.');
  }

  const needsCredit =
    paymentMethod === 'CREDIT' ||
    (
      paymentMethod === 'MIXED' &&
      Number(creditPortion) > 0
    );

  if (needsCredit && !customerId) {
    throw new ApiError(
      400,
      'A customer must be selected for UDHAR / credit payments.'
    );
  }

  if (
    orderType === 'dine_in' &&
    !tableId
  ) {
    throw new ApiError(
      400,
      'A table must be selected for Dine-In orders.'
    );
  }

  const session = await startSession();

  let savedOrder;
  let updatedCustomer = null;

  try {
    await session.withTransaction(async () => {
      const priced = await priceAndValidate({
        items,
        orderType: orderType || 'takeaway',
        adjust: adjustFrom(req.body),
        paymentMethod,
        amountReceived,
        customerId,
        cashPortion,
        upiPortion,
        cardPortion: req.body.cardPortion,
        creditPortion,
        onlinePlatform: req.body.onlinePlatform,
        session,
      });

      let table = null;

      if (tableId) {
        table = await Table.findOne({
          _id: tableId,
          active: true,
        }).session(session);

        if (!table) {
          throw new ApiError(
            404,
            'Selected table not found.'
          );
        }
      }

      const orderNumber =
        await Counter.getNextSequence(
          'orderNumber',
          session
        );
      const invoiceNumber = await nextInvoiceNumber(session);

      const [order] = await Order.create(
        [
          {
            orderNumber,
            invoiceNumber,
            clientRequestId: normalizedClientRequestId,
            items: priced.orderItems,
            ...billFields(priced.bill),
            ...paymentExtras(req.body),
            orderType:
              orderType || 'takeaway',
            orderSource: 'pos',
            table: table
              ? table._id
              : undefined,
            tableCustomerLabel,
            deliveryInfo:
              orderType === 'delivery'
                ? deliveryInfo
                : undefined,
            paymentMethod,
            paymentStatus: 'paid',
            paymentBreakdown:
              priced.paymentBreakdown,
            upiReference: normalizedUpiReference || undefined,
            amountReceived,
            changeReturned:
              priced.changeReturned,
            customer: priced.customer
              ? priced.customer._id
              : undefined,
            notes,
            staff: req.user._id,
            status: 'completed',
            // Staff/POS orders do not use the removed KDS. Mark them as
            // already served so legacy KDS queries never surface them.
            kitchenStatus: 'served',
          },
        ],
        { session }
      );

      // KDS has been removed from the staff APK. POS orders are complete
      // operationally and must not be inserted into the kitchen queue.
      await order.save({ session });

      await applyInventoryAndCredit({
        session,
        req,
        order,
        orderItems: priced.orderItems,
        productMap: priced.productMap,
        customer: priced.customer,
        paymentBreakdown:
          priced.paymentBreakdown,
        grandTotal: priced.grandTotal,
      });

      savedOrder = order;
      updatedCustomer = priced.customer;
    });
  } catch (err) {
    // Race condition: two near-simultaneous requests with the same
    // clientRequestId both passed the pre-check above and one lost the
    // unique-index insert. Treat it as the same success case rather than
    // surfacing a confusing 500/duplicate-key error to the cashier.
    if (err.code === 11000 && normalizedClientRequestId && err.keyPattern?.clientRequestId) {
      const existing = await Order.findOne({ clientRequestId: normalizedClientRequestId })
        .populate('customer', 'name phone')
        .populate('staff', 'name role')
        .populate('table', 'name')
      .populate('items.product', 'name imageUrl');

      if (existing) {
        return res.status(200).json({
          success: true,
          message: 'Bill created successfully.',
          data: { order: existing, customer: existing.customer || null },
        });
      }
    }
    throw err;
  } finally {
    await session.endSession();
  }

  const populated = await Order.findById(
    savedOrder._id
  )
    .populate('customer', 'name phone')
    .populate('staff', 'name role')
    .populate('table', 'name')
      .populate('items.product', 'name imageUrl');

  res.status(201).json({
    success: true,
    message: 'Bill created successfully.',
    data: {
      order: populated,
      customer: updatedCustomer,
    },
  });
});

// POST /api/tables/:tableId/orders
// Creates a normal POS open dine-in order.
const startTableOrder = asyncHandler(
  async (req, res) => {
    await assertBusinessDayOpen();
    const { tableId } = req.params;
    const { tableCustomerLabel } =
      req.body;

    const table = await Table.findOne({
      _id: tableId,
      active: true,
    });

    if (!table) {
      throw new ApiError(
        404,
        'Table not found.'
      );
    }

    const openOrderNumber =
      (
        await Order.countDocuments({
          table: table._id,
          status: 'open',
        })
      ) + 1;

    const order =
      await Order.create({
        orderNumber:
          await Counter.getNextSequence(
            'orderNumber'
          ),
        items: [],
        orderType: 'dine_in',
        orderSource: 'pos',
        table: table._id,
        tableCustomerLabel:
          (typeof tableCustomerLabel === 'string' && tableCustomerLabel.trim().slice(0, 60)) ||
          `Customer ${openOrderNumber}`,
        subtotal: 0,
        grandTotal: 0,
        staff: req.user._id,
        status: 'open',
      });

    res.status(201).json({
      success: true,
      data: order,
    });
  }
);

// PUT /api/orders/:id/items
// Updates items on an open order.
const updateOpenOrderItems =
  asyncHandler(async (req, res) => {
    await assertBusinessDayOpen();
    const {
      items = [],
      discount = 0,
      notes,
      customerId,
      tableCustomerLabel,
    } = req.body;

    if (!Array.isArray(items)) {
      throw new ApiError(400, 'items must be an array.');
    }

    const order =
      await Order.findById(req.params.id);

    if (!order) {
      throw new ApiError(
        404,
        'Order not found.'
      );
    }

    if (order.status !== 'open') {
      throw new ApiError(
        409,
        'This order has already been billed and can no longer be edited.'
      );
    }

    // Same calculation as checkout (services/billing), so the running
    // total on an open tab matches what the final bill will charge.
    const { lines } = items.length > 0
      ? await priceLines(items, { checkStock: false })
      : { lines: [] };
    preserveKotSentQuantities(order.items, lines);

    // Remember the cashier's choices on the tab; checkout reuses them.
    const b = req.body;
    if (b.discountType !== undefined) order.discountType = b.discountType === 'percent' ? 'percent' : 'flat';
    if (b.discountValue !== undefined) order.discountValue = Math.max(0, Number(b.discountValue) || 0);
    else if (b.discount !== undefined && b.discountType === undefined) {
      order.discountType = 'flat';
      order.discountValue = Math.max(0, Number(b.discount) || 0);
    }
    if (b.discountReason !== undefined) order.discountReason = String(b.discountReason || '').trim() || undefined;
    if (b.serviceCharge !== undefined) order.serviceChargeEnabled = b.serviceCharge === null ? undefined : Boolean(b.serviceCharge);
    if (b.packagingCharge !== undefined) order.packagingChargeOverride = b.packagingCharge === null ? undefined : Number(b.packagingCharge);
    if (b.deliveryCharge !== undefined) order.deliveryChargeOverride = b.deliveryCharge === null ? undefined : Number(b.deliveryCharge);

    const settings = await BusinessSettings.getSettings();
    const bill = computeBill({ lines, settings, orderType: order.orderType, adjust: adjustFrom({}, order) });

    order.items = bill.orderItems;
    Object.assign(order, billFields(bill));

    if (notes !== undefined) {
      order.notes = notes;
    }

    // Optional name typed at order time (no customer record needed). It is
    // printed on the bill/KOT when no customer is selected.
    if (typeof tableCustomerLabel === 'string' && tableCustomerLabel.trim()) {
      order.tableCustomerLabel = tableCustomerLabel.trim().slice(0, 60);
    }

    if (customerId !== undefined) {
      if (customerId) {
        const customer = await Customer.findById(customerId).select('_id');
        if (!customer) throw new ApiError(404, 'Selected customer not found.');
      }
      order.customer =
        customerId || undefined;
    }

    await order.save();

    res.json({
      success: true,
      data: order,
    });
  });

// POST /api/orders/open
// Starts a Shopto-style unpaid operational tab for any POS channel.
// QR ordering is deliberately excluded: the public QR flow keeps its own lifecycle.
const startOpenOrder = asyncHandler(async (req, res) => {
  await assertBusinessDayOpen();
  const {
    orderType = 'takeaway',
    tableId,
    tableCustomerLabel,
    customerId,
    deliveryInfo,
    notes,
  } = req.body || {};

  if (!['dine_in', 'takeaway', 'delivery'].includes(orderType)) {
    throw new ApiError(400, 'Invalid order type.');
  }
  if (orderType === 'dine_in' && !tableId) {
    throw new ApiError(400, 'A table is required for dine-in orders.');
  }
  if (orderType !== 'delivery' && deliveryInfo) {
    throw new ApiError(400, 'Delivery details are only valid for delivery orders.');
  }

  const session = await startSession();
  let created;
  try {
    await session.withTransaction(async () => {
      let table;
      if (tableId) {
        table = await Table.findOne({ _id: tableId, active: true }).session(session);
        if (!table) throw new ApiError(404, 'Selected table not found.');
      }

      let customer;
      if (customerId) {
        customer = await Customer.findById(customerId).session(session);
        if (!customer) throw new ApiError(404, 'Selected customer not found.');
      }

      const orderNumber = await Counter.getNextSequence('orderNumber');
      [created] = await Order.create([{
        orderNumber,
        items: [],
        orderType,
        orderSource: 'pos',
        table: table?._id,
        tableCustomerLabel: tableCustomerLabel?.trim() || undefined,
        deliveryInfo: orderType === 'delivery' ? deliveryInfo : undefined,
        customer: customer?._id,
        notes: notes?.trim() || undefined,
        subtotal: 0,
        discount: 0,
        tax: 0,
        grandTotal: 0,
        paymentStatus: 'pending',
        // POS open orders bypass the removed KDS entirely.
        kitchenStatus: 'served',
        status: 'open',
        staff: req.user._id,
      }], { session });
    });
  } finally {
    await session.endSession();
  }

  await audit(req, 'OPEN_ORDER_CREATED', created, { orderType: created.orderType });
  const populated = await Order.findById(created._id)
    .populate('customer', 'name phone')
    .populate('staff', 'name role')
    .populate('table', 'name number');

  res.status(201).json({ success: true, message: 'Order opened.', data: populated });
});

// POST /api/orders/:id/checkout
// Finalizes both normal open orders and QR orders.
const checkoutOrder =
  asyncHandler(async (req, res) => {
    await assertBusinessDayOpen();
    const {
      paymentMethod,
      amountReceived,
      upiReference,
      customerId,
      cashPortion,
      upiPortion,
      creditPortion,
      discount,
    } = req.body;

    // Existing staff UPI/MIXED checkout keeps its current UTR requirement.
    // The only exception is an already server-verified QR payment: that order
    // is already paid and must not be charged/verified a second time at the
    // counter.
    const qrOrder = await Order.findById(req.params.id).select('orderSource paymentStatus');
    const isAlreadyVerifiedQrPayment =
      qrOrder?.orderSource === 'qr' && qrOrder?.paymentStatus === 'paid';

    if (!isAlreadyVerifiedQrPayment &&
        paymentMethod === 'MIXED' &&
        Number(upiPortion) > 0 &&
        (!upiReference || !String(upiReference).trim())) {
      throw new ApiError(400, 'UPI reference / UTR is required for the UPI portion.');
    }

    if (!isAlreadyVerifiedQrPayment &&
        paymentMethod === 'UPI' &&
        (!upiReference || !String(upiReference).trim())) {
      throw new ApiError(400, 'UPI reference / UTR is required before marking payment paid.');
    }

    const normalizedUpiReference = typeof upiReference === 'string' ? upiReference.trim() : '';
    if (normalizedUpiReference.length > 100) {
      throw new ApiError(400, 'UPI reference / UTR is too long.');
    }
    if (normalizedUpiReference) {
      const existingPayment = await Order.findOne({ upiReference: normalizedUpiReference, paymentStatus: 'paid', _id: { $ne: req.params.id } }).select('_id orderNumber');
      if (existingPayment) throw new ApiError(409, `This UPI reference is already used on bill #${existingPayment.orderNumber}.`);
    }

    const session =
      await startSession();

    let finalized;
    let updatedCustomer = null;

    try {
      await session.withTransaction(
        async () => {
          const order =
            await Order.findById(
              req.params.id
            ).session(session);

          if (!order) {
            throw new ApiError(
              404,
              'Order not found.'
            );
          }

          if (!['open', 'preparing', 'ready'].includes(order.status)) {
            throw new ApiError(
              409,
              'This order is not available for checkout.'
            );
          }

          if (
            order.items.length === 0
          ) {
            throw new ApiError(
              400,
              'Add at least one item before checking out.'
            );
          }

          const effectiveCustomerId =
            customerId !== undefined
              ? customerId
              : order.customer;

          const priced =
            await priceAndValidate({
              items:
                order.items.map(
                  (i) => ({
                    productId: i.product,
                    quantity: i.quantity,
                    note: i.note,
                    kotSentQuantity: i.kotSentQuantity,
                    ...(i.quickItem
                      ? { quickItem: i.quickItem }
                      : {}),
                  })
                ),
              orderType: order.orderType,
              // Choices made on the tab, overridden by what the payment
              // screen sends now.
              adjust: adjustFrom(req.body, order),
              paymentMethod,
              amountReceived,
              customerId:
                effectiveCustomerId,
              cashPortion,
              upiPortion,
              cardPortion: req.body.cardPortion,
              creditPortion,
              onlinePlatform: req.body.onlinePlatform,
              session,
            });

          order.items =
            priced.orderItems;
          Object.assign(order, billFields(priced.bill), paymentExtras(req.body));
          if (!order.invoiceNumber) order.invoiceNumber = await nextInvoiceNumber(session);

          order.paymentMethod =
            paymentMethod;
          // Only checkout is allowed to turn a pending payment into paid.
          // The KDS never changes payment state.
          order.paymentStatus = 'paid';

          order.paymentBreakdown =
            priced.paymentBreakdown;

          order.upiReference =
            normalizedUpiReference || undefined;

          order.amountReceived =
            amountReceived;

          order.changeReturned =
            priced.changeReturned;

          order.customer =
            priced.customer
              ? priced.customer._id
              : undefined;

          order.status = 'completed';

          // QR orders start without a staff member.
          // The employee who checks out the order becomes the attendee.
          if (!order.staff) {
            order.staff =
              req.user._id;
          }

          // QR orders keep their existing KOT flow unchanged. Staff/POS
          // orders do not use the removed KDS, so never enqueue a KOT for them.
          if (order.orderSource === 'qr') {
            appendKotFromUnsents(order, req.user._id);
          } else {
            order.kitchenStatus = 'served';
          }
          await order.save({
            session,
          });

          await applyInventoryAndCredit(
            {
              session,
              req,
              order,
              orderItems:
                priced.orderItems,
              productMap:
                priced.productMap,
              customer:
                priced.customer,
              paymentBreakdown:
                priced.paymentBreakdown,
              grandTotal:
                priced.grandTotal,
            }
          );

          finalized = order;
          updatedCustomer =
            priced.customer;
        }
      );
    } finally {
      await session.endSession();
    }

    await audit(req, 'ORDER_CHECKED_OUT', finalized, { paymentMethod: finalized.paymentMethod, amount: finalized.grandTotal });

    const populated =
      await Order.findById(
        finalized._id
      )
        .populate(
          'customer',
          'name phone'
        )
        .populate(
          'staff',
          'name role'
        )
        .populate(
          'table',
          'name'
        );

    res.json({
      success: true,
      message:
        'Bill created successfully.',
      data: {
        order: populated,
        customer:
          updatedCustomer,
      },
    });
  });

// DELETE /api/orders/:id
// Cancels an unpaid open order.
const cancelOpenOrder =
  asyncHandler(async (req, res) => {
    const order =
      await Order.findById(req.params.id);

    if (!order) {
      throw new ApiError(
        404,
        'Order not found.'
      );
    }

    // 'open' covers a brand new QR/table order; 'preparing' covers one the
    // kitchen has already accepted but that still needs to be cancellable
    // (e.g. from the Kitchen Display) before it's billed. Anything billed
    // or already served ('completed', 'ready', 'voided') must go through
    // void instead.
    if (order.status !== 'open' && order.status !== 'preparing' && order.status !== 'ready') {
      throw new ApiError(
        409,
        'Only an unpaid, open or preparing order can be cancelled this way. Use void for completed orders.'
      );
    }

    // A QR order can be paid online before staff check it out. Cancelling it
    // must not silently drop that payment: keep it marked paid and queue a
    // refund so it shows up in the refunds workflow.
    const wasPaid = order.paymentStatus === 'paid';
    order.status = 'voided';
    if (wasPaid) {
      order.refundStatus = 'pending';
      order.refundedAmount = 0;
    } else {
      order.paymentStatus = 'cancelled';
    }
    order.voidedAt = new Date();
    order.voidedBy =
      req.user._id;
    order.voidReason =
      (req.body &&
        req.body.reason) ||
      'Cancelled before payment';

    await order.save();
    await audit(req, 'ORDER_CANCELLED', order, { reason: order.voidReason });

    res.json({
      success: true,
      message: 'Order cancelled.',
    });
  });

// PATCH /api/orders/:id/attendee
// Reassigns the current attendee.
const reassignAttendee =
  asyncHandler(async (req, res) => {
    const { userId } =
      req.body;

    if (!userId) {
      throw new ApiError(
        400,
        'userId is required.'
      );
    }

    const order =
      await Order.findById(
        req.params.id
      );

    if (!order) {
      throw new ApiError(
        404,
        'Order not found.'
      );
    }

    if (
      order.status === 'voided'
    ) {
      throw new ApiError(
        409,
        'Cannot reassign a voided order.'
      );
    }

    const assignee = await User.findOne({ _id: userId, status: 'active' }).select('_id');
    if (!assignee) {
      throw new ApiError(404, 'Selected employee not found or inactive.');
    }

    const now = new Date();

    if (order.staff) {
      // The current attendee's stint began at the previous handover, or at
      // order creation if there has been none.
      const lastHandover = order.attendedByHistory[order.attendedByHistory.length - 1];
      order.attendedByHistory.push({
        user: order.staff,
        from: lastHandover?.to || order.createdAt,
        to: now,
      });
    }

    order.staff = assignee._id;

    await order.save();

    const populated =
      await Order.findById(
        order._id
      ).populate(
        'staff',
        'name role'
      );

    res.json({
      success: true,
      data: populated,
    });
  });

// PATCH /api/orders/:id/table — move an unpaid order to another table.
const shiftOrderToTable = asyncHandler(async (req, res) => {
  const { tableId } = req.body;
  if (!tableId) throw new ApiError(400, 'tableId is required.');

  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (!['open', 'preparing', 'ready'].includes(order.status)) {
    throw new ApiError(409, 'Only an unpaid order can be shifted to another table.');
  }

  const target = await Table.findOne({ _id: tableId, active: true });
  if (!target) throw new ApiError(404, 'Target table not found.');

  order.table = target._id;
  order.orderType = 'dine_in';
  await order.save();

  const populated = await Order.findById(order._id)
    .populate('customer', 'name phone')
    .populate('staff', 'name role')
    .populate('table', 'name')
      .populate('items.product', 'name imageUrl');

  res.json({ success: true, message: `Order shifted to ${target.name}.`, data: populated });
});

// PATCH /api/orders/:id/notes — update special instructions on an unpaid order.
const updateOpenOrderNotes = asyncHandler(async (req, res) => {
  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (!['open', 'preparing', 'ready'].includes(order.status)) {
    throw new ApiError(409, 'Only an unpaid order can update special instructions.');
  }
  order.notes = typeof req.body?.notes === 'string' ? req.body.notes.trim() : '';
  await order.save();
  res.json({ success: true, data: order });
});

// PATCH /api/orders/:id/customer — attach/update the customer on an unpaid order.
const updateOpenOrderCustomer = asyncHandler(async (req, res) => {
  const { customerId } = req.body;
  if (!customerId) throw new ApiError(400, 'customerId is required.');

  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (!['open', 'preparing', 'ready'].includes(order.status)) {
    throw new ApiError(409, 'Only an unpaid order can update customer info.');
  }

  const customer = await Customer.findById(customerId);
  if (!customer) throw new ApiError(404, 'Customer not found.');

  order.customer = customer._id;
  await order.save();

  const populated = await Order.findById(order._id)
    .populate('customer', 'name phone')
    .populate('staff', 'name role')
    .populate('table', 'name')
      .populate('items.product', 'name imageUrl');

  res.json({ success: true, data: populated });
});

// GET /api/orders
// Staff can see:
// 1. Their own orders.
// 2. Unattended QR orders.
// Admin/manager can see all orders.
const listOrders =
  asyncHandler(async (req, res) => {
    const {
      from,
      to,
      paymentMethod,
      staff,
      customer,
      search,
      status,
      orderType,
      table,
    } = req.query;

    const page = Math.max(
      parseInt(req.query.page, 10) ||
        1,
      1
    );

    const limit = Math.min(
      parseInt(req.query.limit, 10) ||
        30,
      200
    );

    const filter = { preLaunchTestData: { $ne: true } };

    if (paymentMethod) {
      filter.paymentMethod =
        paymentMethod;
    }

    if (orderType) {
      filter.orderType =
        orderType;
    }

    if (table) {
      filter.table = table;
    }

    if (customer) {
      filter.customer =
        customer;
    }

    // Normal history shows every order by default -- including open/unbilled
    // ones (a customer QR order awaiting confirmation, or a staff-opened
    // table tab that hasn't been checked out yet) -- so the Orders screen
    // never silently hides an order staff need to act on. Fixes: open POS
    // table orders (orderSource 'pos', status 'open') were previously
    // excluded here (only 'qr' open orders were allowed through), so a
    // just-opened table tab would not appear on the Orders page at all.
    // `status=active` means every unbilled order (open, preparing, ready),
    // regardless of age: used by the table grid so a tab opened before
    // midnight or beyond the first page of results never disappears.
    if (status === 'active') {
      filter.status = { $in: ['open', 'preparing', 'ready'] };
    } else if (status) {
      filter.status = String(status);
    }

    // Staff can see their own orders plus unattended QR orders.
    // Admin and manager can see all orders or filter by staff.
    if (req.user.role === 'staff') {
      if (!status) {
        filter.$or = [
          {
            staff: req.user._id,
          },
          {
            orderSource: 'qr',
            status: 'open',
            staff: {
              $exists: false,
            },
          },
        ];
      } else {
        filter.$or = [
          {
            staff: req.user._id,
          },
          {
            orderSource: 'qr',
            staff: {
              $exists: false,
            },
          },
        ];
      }
    } else if (staff) {
      filter.staff = staff;
    }

    if (from || to) {
      filter.createdAt = {};

      if (from) {
        filter.createdAt.$gte =
          parseClientDate(from);
      }

      if (to) {
        filter.createdAt.$lte =
          parseClientDate(to);
      }
    }

    if (search) {
      const term = String(search).trim();
      const asNumber = Number(term);
      const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const searchRegex = new RegExp(escaped, 'i');
      const matchingCustomers = await Customer.find({
        $or: [{ name: searchRegex }, { phone: searchRegex }],
      }).select('_id').lean();

      const searchOr = [
        ...(term && Number.isFinite(asNumber) ? [{ orderNumber: asNumber }] : []),
        ...(matchingCustomers.length ? [{ customer: { $in: matchingCustomers.map((c) => c._id) } }] : []),
      ];
      // AND the search with any existing $or (the staff visibility rule) so
      // searching can never widen what a staff member is allowed to see.
      // An empty $or is invalid in MongoDB, so "no matches" is expressed as a
      // condition no order can satisfy.
      const searchCondition = searchOr.length ? { $or: searchOr } : { _id: { $exists: false } };
      if (filter.$or) {
        filter.$and = [{ $or: filter.$or }, searchCondition];
        delete filter.$or;
      } else {
        Object.assign(filter, searchCondition);
      }
    }

    const orders =
      await Order.find(filter)
        .populate(
          'customer',
          'name phone'
        )
        .populate(
          'staff',
          'name role'
        )
        .populate(
          'table',
          'name'
        )
        .populate('items.product', 'name imageUrl')
        .sort({
          createdAt: -1,
        })
        .skip(
          (page - 1) * limit
        )
        .limit(limit);

    const total =
      await Order.countDocuments(
        filter
      );

    res.json({
      success: true,
      data: orders,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(
          total / limit
        ),
      },
    });
  });

// GET /api/orders/:id
// Staff can access their own orders and unattended QR orders.
const getOrder =
  asyncHandler(async (req, res) => {
    const baseFilter = {
      _id: req.params.id,
    };

    if (req.user.role === 'staff') {
      baseFilter.$or = [
        {
          staff: req.user._id,
        },
        {
          orderSource: 'qr',
          status: 'open',
          staff: {
            $exists: false,
          },
        },
      ];
    }

    const order =
      await Order.findOne(
        baseFilter
      )
        .populate(
          'customer',
          'name phone'
        )
        .populate(
          'staff',
          'name role'
        )
        .populate(
          'table',
          'name'
        )
        .populate('items.product', 'name imageUrl');

    if (!order) {
      throw new ApiError(
        404,
        'Order not found.'
      );
    }

    res.json({
      success: true,
      data: order,
    });
  });

// PATCH /api/orders/:id/qr-status — advances the kitchen/service status
// of a customer QR order. The employee who accepts it becomes the attendee.
const updateQrOrderStatus =
  asyncHandler(async (req, res) => {
    const { status } = req.body || {};
    const allowed = ['preparing', 'ready', 'served'];

    if (!allowed.includes(status)) {
      throw new ApiError(400, 'Status must be preparing or ready.');
    }

    const order = await Order.findById(req.params.id);
    if (!order) throw new ApiError(404, 'Order not found.');

    // QR status is exclusively for customer QR orders. Normal staff/POS/table
    // orders do not use the kitchen lifecycle because the KDS was removed
    // from the staff APK. This guard also protects old clients from
    // accidentally putting normal orders back into kitchen workflow.
    if (order.orderSource !== 'qr') {
      throw new ApiError(409, 'Kitchen workflow is only available for QR orders.');
    }

    if (!['open', 'preparing', 'ready'].includes(order.status)) {
      throw new ApiError(409, 'This order is already closed.');
    }

    const currentKitchen = order.kitchenStatus || (order.status === 'ready' ? 'ready' : order.status === 'preparing' ? 'preparing' : 'new');
    const validTransition =
      (currentKitchen === 'new' && status === 'preparing') ||
      (currentKitchen === 'preparing' && status === 'ready') ||
      (currentKitchen === 'ready' && status === 'served');

    if (!validTransition) {
      throw new ApiError(409, `Cannot move order from ${order.status} to ${status}.`);
    }

    if (!order.staff) order.staff = req.user._id;
    const previousStatus = order.status;
    order.kitchenStatus = status;
    if (status !== 'served') order.status = status;
    if (status === 'preparing') {
      order.estimatedReadyAt = new Date(Date.now() + 20 * 60 * 1000);
    }
    if (status === 'ready') order.estimatedReadyAt = new Date();
    await order.save();
    await audit(req, status === 'preparing' ? 'QR_ORDER_ACCEPTED' : 'QR_ORDER_READY', order, { from: previousStatus, to: status });

    const populated = await Order.findById(order._id)
      .populate('staff', 'name role')
      .populate('table', 'name number')
      .populate('items.product', 'name imageUrl');

    res.json({ success: true, message: `Order marked ${status}.`, data: populated });
  });

// POST /api/orders/:id/kot — send only newly-added quantities to kitchen.
const createKot = asyncHandler(async (req, res) => {
  await assertBusinessDayOpen();
  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status === 'voided') throw new ApiError(409, 'Cannot send KOT for a voided order.');
  if (!order.items.length) throw new ApiError(400, 'Add items before sending a KOT.');

  const kot = appendKotFromUnsents(order, req.user._id);
  if (!kot) throw new ApiError(409, 'No new items to send. All current quantities are already in the kitchen.');
  // The KDS is no longer part of the staff APK. Keep QR behavior exactly as
  // before; for staff/POS orders a KOT is only a printable ticket and must not
  // put the order back into the legacy KDS queue.
  if (order.orderSource !== 'qr') order.kitchenStatus = 'served';
  await order.save();

  const populated = await Order.findById(order._id)
    .populate('staff', 'name role')
    .populate('table', 'name number')
    .populate('items.product', 'name imageUrl');

  await audit(req, 'KOT_CREATED', order, { kotNumber: kot.kotNumber, itemCount: kot.items.length });
  res.status(201).json({ success: true, message: `KOT #${kot.kotNumber} sent to kitchen.`, data: { order: populated, kot } });
});

// PATCH /api/orders/:id/kitchen-status — shared KDS state machine.
const updateKitchenStatus = asyncHandler(async (req, res) => {
  const { status } = req.body || {};
  const allowed = ['preparing', 'ready', 'served'];
  if (!allowed.includes(status)) throw new ApiError(400, 'Status must be preparing, ready or served.');

  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status === 'voided') throw new ApiError(409, 'This order is cancelled.');

  // Kitchen Display was removed from the staff APK. Only customer QR orders
  // use the kitchen lifecycle. Normal staff/POS/table orders must never enter
  // or be advanced through KDS, even if an older record has a stale status.
  if (order.orderSource !== 'qr') {
    order.kitchenStatus = 'served';
    await order.save();
    return res.json({ success: true, message: 'Kitchen workflow is not used for staff orders.', data: order });
  }

  const current = order.kitchenStatus || (order.status === 'ready' ? 'ready' : order.status === 'preparing' ? 'preparing' : 'new');
  const valid = (current === 'new' && status === 'preparing') ||
      (current === 'preparing' && status === 'ready') ||
      (current === 'ready' && status === 'served');
  if (!valid) throw new ApiError(409, `Cannot move kitchen order from ${current} to ${status}.`);

  order.kitchenStatus = status;
  if (status === 'preparing') {
    order.estimatedReadyAt = new Date(Date.now() + 20 * 60 * 1000);
    if (order.status === 'open') order.status = 'preparing';
    if (!order.staff) order.staff = req.user._id;
  } else if (status === 'ready') {
    order.estimatedReadyAt = new Date();
    if (order.status === 'preparing') order.status = 'ready';
  }

  await order.save();
  await audit(req, `KITCHEN_${status.toUpperCase()}`, order, { from: current, to: status });

  const populated = await Order.findById(order._id)
    .populate('staff', 'name role')
    .populate('table', 'name number')
    .populate('items.product', 'name imageUrl');
  res.json({ success: true, message: `Kitchen order marked ${status}.`, data: populated });
});

// POST /api/orders/:id/refund
// Records the actual money reversal separately from bill voiding.
const refundOrder = asyncHandler(async (req, res) => {
  const order = await Order.findById(req.params.id);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status !== 'voided') throw new ApiError(409, 'Void the bill before recording a refund.');
  if (order.refundStatus === 'refunded') throw new ApiError(409, 'Refund is already recorded.');
  // Only real money (cash/UPI) can be refunded. The credit (UDHAR) portion was
  // never paid, and voiding already reversed it on the customer's ledger.
  const paidCash = round2(order.paymentBreakdown?.cash || 0);
  const paidUpi = round2(order.paymentBreakdown?.upi || 0);
  const paidAmount = round2(paidCash + paidUpi);
  if (order.refundStatus === 'not_required' || paidAmount <= 0) {
    throw new ApiError(409, 'No cash or UPI payment on this bill needs a refund.');
  }
  const amount = round2(Number(req.body.amount ?? paidAmount));
  if (!Number.isFinite(amount) || amount <= 0 || amount > paidAmount) throw new ApiError(400, 'Refund cannot exceed the amount actually paid.');
  const defaultMethod = paidCash > 0 && paidUpi > 0 ? 'MIXED' : paidUpi > 0 ? 'UPI' : 'CASH';
  const method = req.body.method || defaultMethod;
  if (!['CASH','UPI','MIXED'].includes(method)) throw new ApiError(400, 'Invalid refund method.');
  if (method === 'CASH' && amount > paidCash) throw new ApiError(400, 'Cash refund exceeds cash paid.');
  if (method === 'UPI' && amount > paidUpi) throw new ApiError(400, 'UPI refund exceeds UPI paid.');
  if (method === 'UPI' && !String(req.body.reference || '').trim()) throw new ApiError(400, 'UPI refund reference is required.');
  const businessDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
  const day = await DayClose.findOne({ businessDate });
  if (day?.status === 'closed') throw new ApiError(409, 'Business day is closed. Refunds cannot be recorded.');
  const refund = await RefundTransaction.create({ order: order._id, amount, method, reference: req.body.reference, processedBy: req.user._id, note: req.body.note });
  order.refundStatus = 'refunded';
  order.refundedAmount = amount;
  order.refundedAt = refund.processedAt;
  order.refundReference = refund.reference;
  await order.save();
  await audit(req, 'ORDER_REFUNDED', order, { amount, method, reference: refund.reference });
  res.status(201).json({ success: true, data: { order, refund } });
});

// POST /api/orders/:id/void
// Reverses inventory and credit effects.
const voidOrder =
  asyncHandler(async (req, res) => {
    await assertBusinessDayOpen();
    const { reason } =
      req.body;

    const session =
      await startSession();

    let voided;

    try {
      await session.withTransaction(
        async () => {
          const order =
            await Order.findById(
              req.params.id
            ).session(session);

          if (!order) {
            throw new ApiError(
              404,
              'Order not found.'
            );
          }

          if (
            order.status ===
            'voided'
          ) {
            throw new ApiError(
              409,
              'Order is already voided.'
            );
          }

          // Stock and credit are only applied at checkout, so only a completed
          // bill has anything to reverse. Voiding an unbilled preparing/ready
          // order would restock inventory that was never deducted.
          if (
            order.status !== 'completed'
          ) {
            throw new ApiError(
              409,
              'This order has not been billed yet - cancel it instead of voiding.'
            );
          }

          // Restore the exact product stock consumed by the sale.
          for (const line of order.items) {
            const product = await Product.findById(line.product).session(session);
            if (!product || !product.trackInventory) continue;
            product.stock += line.quantity;
            await product.save({ session });
            await InventoryTransaction.create([{ product: product._id, type: 'VOID_RESTOCK', quantity: line.quantity, stockAfter: product.stock, reason: `Void of bill #${order.orderNumber}`, order: order._id, recordedBy: req.user._id }], { session });
          }

          // Reverse credit ledger effect.
          if (
            order.customer &&
            order.paymentBreakdown.credit >
              0
          ) {
            const customer =
              await Customer.findById(
                order.customer
              ).session(session);

            if (customer) {
              customer.outstandingBalance =
                round2(
                  customer.outstandingBalance -
                    order
                      .paymentBreakdown
                      .credit
                );

              await customer.save({
                session,
              });

              await CreditTransaction.create(
                [
                  {
                    customer:
                      customer._id,
                    type: 'PAID',
                    amount:
                      order
                        .paymentBreakdown
                        .credit,
                    method:
                      'ORDER',
                    order:
                      order._id,
                    balanceAfter:
                      customer.outstandingBalance,
                    note:
                      `Reversal - void of bill #${order.orderNumber}`,
                    recordedBy:
                      req.user._id,
                  },
                ],
                { session }
              );
            }
          }

          // Every completed bill with a customer added its grandTotal to the
          // customer's lifetime purchases, whatever the payment method.
          if (order.customer) {
            await Customer.updateOne(
              { _id: order.customer },
              { $inc: { totalPurchases: -order.grandTotal } },
              { session }
            );
          }

          order.status =
            'voided';

          order.voidedAt =
            new Date();

          order.voidedBy =
            req.user._id;

          order.voidReason =
            reason;

          if (order.paymentBreakdown && (order.paymentBreakdown.cash > 0 || order.paymentBreakdown.upi > 0)) {
            order.refundStatus = 'pending';
            order.refundedAmount = 0;
          } else {
            order.refundStatus = 'not_required';
            order.refundedAmount = 0;
          }

          await order.save({
            session,
          });

          voided = order;
        }
      );
    } finally {
      await session.endSession();
    }

    await audit(req, 'ORDER_VOIDED', voided, { reason: voided.voidReason });
    res.json({
      success: true,
      message: 'Order voided.',
      data: voided,
    });
  });

// POST /api/orders/quote
// Bill preview for the cart / payment screen: same calculation as the final
// bill (GST per rate, charges, round-off), nothing is saved.
const quoteOrder = asyncHandler(async (req, res) => {
  const { items = [], orderType = 'takeaway' } = req.body;
  const settings = await BusinessSettings.getSettings();
  const { lines } = Array.isArray(items) && items.length > 0
    ? await priceLines(items, { checkStock: false })
    : { lines: [] };
  const bill = computeBill({
    lines,
    settings,
    orderType,
    adjust: { ...adjustFrom(req.body), complimentary: req.body.paymentMethod === 'COMPLIMENTARY' || req.body.complimentary },
  });
  res.json({ success: true, data: bill });
});

async function loadOpenOrder(id, session) {
  const order = await Order.findById(id).session(session);
  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status !== 'open') throw new ApiError(409, 'Only an unbilled (open) order can be changed.');
  return order;
}

/** Re-prices an open order's current items (after split/merge). */
async function repriceOpenOrder(order, session) {
  const settings = await BusinessSettings.getSettings(session);
  const lines = order.items.map((i) => (i.toObject ? i.toObject() : i));
  const bill = computeBill({ lines, settings, orderType: order.orderType, adjust: adjustFrom({}, order) });
  order.items = bill.orderItems;
  Object.assign(order, billFields(bill));
}

// POST /api/orders/:id/split  { lines: [{ index, quantity }], label? }
// Moves some items of an open order into a new open order on the same
// table/counter, so one group can pay separately.
const splitOpenOrder = asyncHandler(async (req, res) => {
  await assertBusinessDayOpen();
  const moves = Array.isArray(req.body.lines) ? req.body.lines : [];
  if (moves.length === 0) throw new ApiError(400, 'Choose at least one item to move.');

  const session = await startSession();
  let created;
  let source;
  try {
    await session.withTransaction(async () => {
      source = await loadOpenOrder(req.params.id, session);
      const moved = [];
      for (const move of moves) {
        const line = source.items[Number(move.index)];
        const quantity = Number(move.quantity);
        if (!line || !Number.isInteger(quantity) || quantity < 1 || quantity > line.quantity) {
          throw new ApiError(400, 'Invalid item or quantity to move.');
        }
        // Kitchen-sent quantity moves with the items.
        const sentMoved = Math.min(Number(line.kotSentQuantity || 0), quantity);
        const copy = line.toObject();
        moved.push({ ...copy, quantity, total: round2(copy.price * quantity), kotSentQuantity: sentMoved });
        line.quantity -= quantity;
        line.kotSentQuantity = Number(line.kotSentQuantity || 0) - sentMoved;
      }
      source.items = source.items.filter((l) => l.quantity > 0);
      if (source.items.length === 0) throw new ApiError(400, 'Leave at least one item on the original bill.');
      await repriceOpenOrder(source, session);
      await source.save({ session });

      const orderNumber = await Counter.getNextSequence('orderNumber', session);
      const label = String(req.body.label || '').trim() || `${source.tableCustomerLabel || 'Customer'} (split)`;
      const [order] = await Order.create([{
        orderNumber,
        items: moved,
        orderType: source.orderType,
        orderSource: 'pos',
        table: source.table,
        tableCustomerLabel: label.slice(0, 60),
        deliveryInfo: source.deliveryInfo,
        subtotal: 0,
        grandTotal: 0,
        paymentStatus: 'pending',
        kitchenStatus: source.kitchenStatus,
        status: 'open',
        staff: req.user._id,
      }], { session });
      await repriceOpenOrder(order, session);
      await order.save({ session });
      created = order;
    });
  } finally {
    await session.endSession();
  }
  await audit(req, 'ORDER_SPLIT', source, { into: created.orderNumber });
  res.status(201).json({ success: true, data: { order: source, newOrder: created } });
});

// POST /api/orders/:id/merge  { fromOrderId }
// Moves every item of another open order into this one and closes the other
// (e.g. two tables joined into one bill).
const mergeOpenOrders = asyncHandler(async (req, res) => {
  await assertBusinessDayOpen();
  if (!req.body.fromOrderId || String(req.body.fromOrderId) === String(req.params.id)) {
    throw new ApiError(400, 'Choose another open order to merge.');
  }
  const session = await startSession();
  let target;
  let from;
  try {
    await session.withTransaction(async () => {
      target = await loadOpenOrder(req.params.id, session);
      from = await loadOpenOrder(req.body.fromOrderId, session);
      for (const line of from.items) {
        const key = orderLineKey(line);
        const same = target.items.find((l) => orderLineKey(l) === key && (l.note || '') === (line.note || ''));
        if (same) {
          same.quantity += line.quantity;
          same.kotSentQuantity = Number(same.kotSentQuantity || 0) + Number(line.kotSentQuantity || 0);
        } else {
          target.items.push(line.toObject());
        }
      }
      target.kots.push(...from.kots.map((k) => k.toObject()));
      await repriceOpenOrder(target, session);
      await target.save({ session });

      from.items = [];
      from.status = 'voided';
      from.voidedAt = new Date();
      from.voidedBy = req.user._id;
      from.voidReason = `Merged into bill #${target.orderNumber}`;
      await from.save({ session });
    });
  } finally {
    await session.endSession();
  }
  // A table left without open orders becomes available again.
  if (from.table && String(from.table) !== String(target.table || '')) {
    const stillOpen = await Order.exists({ table: from.table, status: { $in: ['open', 'preparing', 'ready'] } });
    if (!stillOpen) await Table.updateOne({ _id: from.table, status: 'occupied' }, { status: 'available' });
  }
  await audit(req, 'ORDER_MERGED', target, { from: from.orderNumber });
  res.json({ success: true, data: { order: target } });
});

module.exports = {
  createOrder,
  quoteOrder,
  splitOpenOrder,
  mergeOpenOrders,
  createKot,
  updateKitchenStatus,
  startTableOrder,
  startOpenOrder,
  updateOpenOrderItems,
  checkoutOrder,
  updateQrOrderStatus,
  cancelOpenOrder,
  reassignAttendee,
  shiftOrderToTable,
  updateOpenOrderCustomer,
  updateOpenOrderNotes,
  listOrders,
  getOrder,
  voidOrder,
  refundOrder,
};
