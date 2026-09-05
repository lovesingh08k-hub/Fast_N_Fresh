const mongoose = require('mongoose');
const { Product, Category, Table, Order, Counter, BusinessSettings } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { pushNewOrderAlert } = require('../utils/push');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function normalizeClientRequestId(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  if (!id) return undefined;
  if (id.length > 100 || !/^[A-Za-z0-9._:-]+$/.test(id)) {
    throw new ApiError(400, 'Invalid client request id.');
  }
  return id;
}

const MAX_QUANTITY_PER_ITEM = 50; // guards against absurd/abusive quantities from a public endpoint

// GET /api/public/menu — read-only, customer-safe view of the catalog.
// Only ever returns fields a customer is allowed to see; no cost price,
// stock counts, low-stock thresholds, or soft-deleted/unavailable-category
// data ever leaves this endpoint.
const getPublicMenu = asyncHandler(async (req, res) => {
  const categories = await Category.find({ status: 'active' }).sort({ sortOrder: 1, name: 1 }).select('_id name sortOrder');

  const products = await Product.find({ isDeleted: false })
    .populate('category', 'name status')
    .sort({ name: 1 })
    .select('_id name category sellingPrice imageUrl status');

  const items = products
    .filter((p) => p.category && p.category.status === 'active')
    .map((p) => ({
      _id: p._id,
      name: p.name,
      category: p.category._id,
      categoryName: p.category.name,
      price: p.sellingPrice,
      image: p.imageUrl || '',
      available: p.status === 'available',
    }));

  res.json({
    success: true,
    categories: categories.map((c) => ({ _id: c._id, name: c.name })),
    items,
  });
});

// GET /api/public/tables/:number — resolves a QR table number to a display
// name and confirms it's a real, active table before the customer even
// starts browsing. Never trusts the number blindly: it must match an
// active Table document.
const getPublicTable = asyncHandler(async (req, res) => {
  const number = Number(req.params.number);
  if (!Number.isInteger(number) || number < 1) {
    throw new ApiError(400, 'Invalid table.');
  }

  const table = await Table.findOne({ number, active: true }).select('_id name number');
  if (!table) {
    throw new ApiError(404, 'This table QR code is not recognized. Please ask staff for help.');
  }

  res.json({ success: true, data: { tableId: table._id, tableNumber: table.number, tableName: table.name } });
});

// Shared success response shape for a newly created (or idempotently
// re-returned) QR order.
function publicOrderResponse(order, table) {
  return {
    success: true,
    message: 'Order placed successfully.',
    data: {
      orderId: order._id,
      orderNumber: order.orderNumber,
      tableNumber: table ? table.number : order.table,
      tableName: table ? table.name : undefined,
      items: order.items,
      total: order.grandTotal,
      paymentMethod: order.paymentMethod,
      paymentStatus: order.paymentStatus || (order.status === 'completed' ? 'paid' : 'pending'),
      status: order.status,
      estimatedReadyAt: order.estimatedReadyAt,
      updatedAt: order.updatedAt,
      trackingToken: order.clientRequestId,
    },
  };
}

// GET /api/public/payment-options — exposes only customer-safe payment configuration.
const getPublicPaymentOptions = asyncHandler(async (req, res) => {
  const settings = await BusinessSettings.getSettings();
  res.json({
    success: true,
    data: {
      upiId: String(settings.upiId || '').trim(),
      cafeName: settings.cafeName || 'FAST N FRESH CAFE',
      // onlineUpi is derived from the same value returned to the customer.
      // This prevents the checkout from hiding UPI when an ID is configured.
      onlineUpi: Boolean(String(settings.upiId || '').trim()),
    },
  });
});

// POST /api/public/orders — places a customer order from the QR menu.
// Creates an OPEN dine-in order only after the customer explicitly presses
// Place Order. The UPI app is an external payment handoff; returning from it
// never creates or marks an order paid. Staff can handle final settlement
// through the existing POS workflow.
const createPublicOrder = asyncHandler(async (req, res) => {
  const { tableNumber, customerName, customerPhone, items, note, clientRequestId, paymentMethod, upiReference } = req.body;
  const normalizedClientRequestId = normalizeClientRequestId(clientRequestId);

  // Idempotency: a customer on a flaky connection (or a page that retries
  // after a Render cold-start timeout) can resend the exact same submit.
  // If we've already recorded an order for this clientRequestId, return
  // that order instead of placing a second one on the table.
  if (normalizedClientRequestId) {
    const existing = await Order.findOne({ clientRequestId: normalizedClientRequestId }).populate('table', 'name number');
    if (existing) {
      return res.status(200).json(publicOrderResponse(existing, existing.table));
    }
  }

  const normalizedPaymentMethod = paymentMethod === 'UPI' ? 'UPI' : 'CASH';
  const normalizedUpiReference = typeof upiReference === 'string' ? upiReference.trim() : '';
  if (normalizedPaymentMethod === 'CASH' && normalizedUpiReference) {
    throw new ApiError(400, 'UPI reference can only be sent with UPI payment.');
  }
  if (normalizedUpiReference.length > 100) {
    throw new ApiError(400, 'UPI reference is too long.');
  }

  const tableNum = Number(tableNumber);
  if (!Number.isInteger(tableNum) || tableNum < 1) {
    throw new ApiError(400, 'Invalid table number.');
  }

  if (customerName !== undefined && typeof customerName !== 'string') {
    throw new ApiError(400, 'Invalid customer name.');
  }
  if (customerName && customerName.trim().length > 100) {
    throw new ApiError(400, 'Customer name is too long.');
  }
  const normalizedCustomerName = typeof customerName === 'string' ? customerName.trim() : '';
  const normalizedCustomerPhone = typeof customerPhone === 'string' ? customerPhone.trim() : '';
  if (!normalizedCustomerName && !normalizedCustomerPhone) {
    throw new ApiError(400, 'Customer name or phone number is required.');
  }
  if (customerPhone !== undefined && customerPhone !== null && customerPhone !== '') {
    if (typeof customerPhone !== 'string' || !/^[0-9+\-\s]{6,20}$/.test(customerPhone.trim())) {
      throw new ApiError(400, 'Invalid phone number.');
    }
  }
  if (note !== undefined && (typeof note !== 'string' || note.length > 300)) {
    throw new ApiError(400, 'Note is too long.');
  }

  if (!Array.isArray(items) || items.length === 0) {
    throw new ApiError(400, 'Your cart is empty. Add at least one item.');
  }
  if (items.length > 50) {
    throw new ApiError(400, 'Too many distinct items in one order.');
  }

  // Validate/normalize item shape before touching the DB. Client-supplied
  // price/total/name are read nowhere below — only productId and quantity
  // are trusted, and even those are re-validated against the DB.
  const requestedItems = [];
  const seenProductIds = new Set();
  for (const raw of items) {
    const productId = raw && (raw.productId || raw.product);
    const quantity = Number(raw && raw.quantity);

    if (!productId || !mongoose.Types.ObjectId.isValid(productId)) {
      throw new ApiError(400, 'One of the items in your cart is invalid.');
    }
    if (!Number.isInteger(quantity) || quantity < 1) {
      throw new ApiError(400, 'Item quantities must be whole numbers of at least 1.');
    }
    if (quantity > MAX_QUANTITY_PER_ITEM) {
      throw new ApiError(400, `Quantity too high for one item (max ${MAX_QUANTITY_PER_ITEM}).`);
    }
    if (seenProductIds.has(String(productId))) {
      throw new ApiError(400, 'Duplicate item in cart. Please refresh and try again.');
    }
    seenProductIds.add(String(productId));
    requestedItems.push({ productId, quantity });
  }

  const table = await Table.findOne({ number: tableNum, active: true });
  if (!table) {
    throw new ApiError(404, 'This table QR code is not recognized. Please ask staff for help.');
  }

  const productIds = requestedItems.map((i) => i.productId);
  const products = await Product.find({ _id: { $in: productIds }, isDeleted: false }).populate('category', 'status');
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const orderItems = [];
  let subtotal = 0;

  for (const { productId, quantity } of requestedItems) {
    const product = productMap.get(String(productId));
    if (!product) throw new ApiError(400, 'One of the items in your cart is no longer available.');
    if (product.status !== 'available' || !product.category || product.category.status !== 'active') {
      throw new ApiError(400, `${product.name} is currently unavailable.`);
    }

    // Server-calculated price and line total only — client values are
    // never read or trusted anywhere in this flow.
    const lineTotal = round2(product.sellingPrice * quantity);
    subtotal = round2(subtotal + lineTotal);
    orderItems.push({ product: product._id, name: product.name, price: product.sellingPrice, quantity, total: lineTotal });
  }

  const settings = await BusinessSettings.getSettings();
  const tax = settings.taxEnabled ? round2((subtotal * settings.taxPercent) / 100) : 0;
  const grandTotal = round2(subtotal + tax);

  const orderNumber = await Counter.getNextSequence('orderNumber');

  // A QR order is NOT financially settled just because the customer chose
  // UPI, was handed off to a UPI app, or later returns and enters a UTR.
  // Settlement (paymentStatus = 'paid') happens ONLY at authenticated staff
  // checkout (see orderController.checkoutOrder), after a human confirms
  // the money actually arrived. For UPI, order creation IS the payment
  // "initiation" moment — the DB now tracks that state explicitly so staff
  // can see it, instead of it only living in the customer's browser.
  const initialPaymentStatus = normalizedPaymentMethod === 'UPI' ? 'payment_initiated' : 'pending';

  let order;
  try {
    order = await Order.create({
      orderNumber,
      clientRequestId: normalizedClientRequestId,
      items: orderItems,
      orderType: 'dine_in',
      orderSource: 'qr',
      table: table._id,
      tableCustomerLabel: (customerName && customerName.trim()) || undefined,
      qrCustomerContact: {
        name: (customerName && customerName.trim()) || undefined,
        phone: (customerPhone && customerPhone.trim()) || undefined,
      },
      subtotal,
      tax,
      grandTotal,
      paymentMethod: normalizedPaymentMethod,
      paymentStatus: initialPaymentStatus,
      paymentInitiatedAt: initialPaymentStatus === 'payment_initiated' ? new Date() : undefined,
      paymentBreakdown: { cash: 0, upi: 0, credit: 0 },
      upiReference: normalizedUpiReference || undefined,
      notes: note ? note.trim() : undefined,
      status: 'open',
      estimatedReadyAt: undefined,
      // staff intentionally omitted — schema allows this for orderSource 'qr';
      // it gets set automatically when staff checks the order out.
    });
  } catch (err) {
    // Two near-simultaneous submits with the same clientRequestId both
    // passed the pre-check above and one lost the unique-index insert.
    // Treat it as the same success case instead of surfacing a confusing
    // error to the customer.
    if (err.code === 11000 && normalizedClientRequestId && err.keyPattern?.clientRequestId) {
      const existing = await Order.findOne({ clientRequestId: normalizedClientRequestId }).populate('table', 'name number');
      if (existing) {
        return res.status(200).json(publicOrderResponse(existing, existing.table));
      }
    }
    throw err;
  }

  // Best-effort push so admin/manager/staff get a real notification even
  // if the app is fully closed on their phone -- deliberately not
  // awaited-and-failed-on: a push problem must never block the customer's
  // order from succeeding.
  pushNewOrderAlert(order).catch(() => {});

  res.status(201).json(publicOrderResponse(order, table));
});




// POST /api/public/orders/:id/upi-reference — customer submits the UTR/
// reference number after returning from their UPI app.
//
// IMPORTANT: this does NOT mark the order paid. It only records what the
// customer claims to have paid with. paymentStatus stays 'payment_initiated'
// (awaiting a human to verify and check the order out as paid). There is
// currently no payment gateway/webhook wired up to this project that could
// verify a UPI transaction automatically — see the note in
// getPublicPaymentOptions' caller / project docs for what would be needed
// to add that.
const submitPublicUpiReference = asyncHandler(async (req, res) => {
  const token = String(req.body?.token || req.query.token || '').trim();
  if (!token) throw new ApiError(400, 'Tracking token is required.');

  const rawReference = req.body?.upiReference;
  const upiReference = typeof rawReference === 'string' ? rawReference.trim() : '';
  if (!upiReference) throw new ApiError(400, 'Please enter your UPI reference / UTR.');
  if (upiReference.length > 100) throw new ApiError(400, 'UPI reference is too long.');
  if (!/^[A-Za-z0-9/_-]{4,100}$/.test(upiReference)) {
    throw new ApiError(400, 'That doesn\'t look like a valid UPI reference / UTR.');
  }

  const order = await Order.findOne({
    _id: req.params.id,
    clientRequestId: token,
    orderSource: 'qr',
  }).populate('table', 'name number');

  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.paymentMethod !== 'UPI') throw new ApiError(400, 'This order is not a UPI payment.');
  if (order.status === 'voided' || order.paymentStatus === 'cancelled') {
    throw new ApiError(409, 'This order was cancelled.');
  }
  if (order.paymentStatus === 'paid') {
    // Idempotent: customer double-tapped submit after staff already
    // verified it. Not an error.
    return res.json(publicOrderResponse(order, order.table));
  }
  if (order.paymentStatus !== 'payment_initiated') {
    throw new ApiError(409, 'This order cannot accept a UPI reference right now.');
  }

  // A UTR must be unique across already-verified payments — prevents one
  // real payment's reference being reused across multiple unpaid orders.
  const existingPayment = await Order.findOne({
    upiReference,
    paymentStatus: 'paid',
    _id: { $ne: order._id },
  }).select('_id');
  if (existingPayment) {
    throw new ApiError(409, 'This UPI reference has already been used for another order. Please double-check the UTR.');
  }

  order.upiReference = upiReference;
  await order.save();

  res.json(publicOrderResponse(order, order.table));
});

// POST /api/public/orders/:id/cancel?token=<clientRequestId>
// Cancels a QR order that was created for a payment attempt but was not
// completed. The clientRequestId is required so a customer cannot cancel
// another customer's order by guessing an order id.
const cancelPublicOrder = asyncHandler(async (req, res) => {
  const token = String(req.query.token || req.body?.token || '').trim();
  if (!token) throw new ApiError(400, 'Tracking token is required.');

  const order = await Order.findOne({
    _id: req.params.id,
    clientRequestId: token,
    orderSource: 'qr',
  });

  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status === 'voided') {
    return res.json({ success: true, message: 'Order cancelled.' });
  }
  if (order.status !== 'open') {
    throw new ApiError(409, 'This order can no longer be cancelled.');
  }

  order.status = 'voided';
  order.paymentStatus = 'cancelled';
  order.voidedAt = new Date();
  order.voidReason = order.paymentMethod === 'UPI' ? 'Customer cancelled UPI payment.' : 'Customer cancelled order.';
  await order.save();

  res.json({ success: true, message: 'Order cancelled.' });
});

// GET /api/public/orders/:id/status?token=<clientRequestId> — customer-safe
// order tracking. The idempotency token acts as a lightweight private
// tracking secret so a random order ID alone cannot expose another customer's
// order details.
const getPublicOrderStatus = asyncHandler(async (req, res) => {
  const token = String(req.query.token || '').trim();
  if (!token) throw new ApiError(400, 'Tracking token is required.');

  const order = await Order.findOne({
    _id: req.params.id,
    clientRequestId: token,
    orderSource: 'qr',
  }).populate('table', 'name number');

  if (!order) throw new ApiError(404, 'Order tracking information was not found.');

  res.json({
    success: true,
    data: {
      orderId: order._id,
      orderNumber: order.orderNumber,
      tableNumber: order.table?.number,
      tableName: order.table?.name,
      customerName: order.qrCustomerContact?.name,
      items: order.items,
      total: order.grandTotal,
      paymentMethod: order.paymentMethod,
      paymentStatus: order.paymentStatus || (order.status === 'completed' ? 'paid' : 'pending'),
      status: order.status,
      estimatedReadyAt: order.estimatedReadyAt,
      note: order.notes,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    },
  });
});

module.exports = {
  getPublicMenu,
  getPublicTable,
  getPublicPaymentOptions,
  createPublicOrder,
  submitPublicUpiReference,
  cancelPublicOrder,
  getPublicOrderStatus,
};
