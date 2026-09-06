const mongoose = require('mongoose');
const { Product, Table, BusinessSettings, PaymentTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { getPaymentProvider } = require('../services/paymentProvider');
const { finalizeVerifiedPayment } = require('../services/paymentService');
const { pushNewOrderAlert } = require('../utils/push');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function normalizeClientRequestId(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  if (!id || id.length > 100 || !/^[A-Za-z0-9._:-]+$/.test(id)) {
    throw new ApiError(400, 'Invalid client request id.');
  }
  return id;
}

// POST /api/public/payments
//
// Creates ONLY a payment transaction/draft. It deliberately does not create
// an Order. A real provider adapter must return a provider transaction/checkout
// reference. The final Order is created only after server-side verification.
const createPublicPayment = asyncHandler(async (req, res) => {
  const {
    tableNumber,
    customerName,
    customerPhone,
    items,
    note,
    clientRequestId,
  } = req.body || {};

  const requestId = normalizeClientRequestId(clientRequestId);

  const existing = await PaymentTransaction.findOne({ clientRequestId })
    .populate('table', 'name number');
  if (existing) {
    if (existing.status === 'succeeded' && existing.orderId) {
      return res.json({
        success: true,
        data: {
          transactionId: existing._id,
          status: existing.status,
          orderId: existing.orderId,
        },
      });
    }
    if (existing.status === 'initiated' || existing.status === 'processing') {
      return res.json({
        success: true,
        data: {
          transactionId: existing._id,
          status: existing.status,
          checkoutUrl: existing.providerPayload?.checkoutUrl || null,
          providerPaymentId: existing.providerPaymentId || null,
        },
      });
    }
    throw new ApiError(409, 'This payment attempt is no longer active. Please try again.');
  }

  const tableNum = Number(tableNumber);
  if (!Number.isInteger(tableNum) || tableNum < 1) {
    throw new ApiError(400, 'Invalid table number.');
  }

  const normalizedName = typeof customerName === 'string' ? customerName.trim() : '';
  const normalizedPhone = typeof customerPhone === 'string' ? customerPhone.trim() : '';
  if (!normalizedName && !normalizedPhone) {
    throw new ApiError(400, 'Please enter your name or phone number before paying.');
  }
  if (normalizedName.length > 100) throw new ApiError(400, 'Customer name is too long.');
  if (normalizedPhone && !/^[0-9+\-\s]{6,20}$/.test(normalizedPhone)) {
    throw new ApiError(400, 'Invalid phone number.');
  }
  if (note !== undefined && (typeof note !== 'string' || note.length > 300)) {
    throw new ApiError(400, 'Note is too long.');
  }
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new ApiError(400, 'Your cart is empty or contains too many distinct items.');
  }

  const seen = new Set();
  const requested = [];
  for (const raw of items) {
    const productId = raw && (raw.productId || raw.product);
    const quantity = Number(raw && raw.quantity);
    if (!productId || !mongoose.Types.ObjectId.isValid(productId)) {
      throw new ApiError(400, 'One of the items in your cart is invalid.');
    }
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) {
      throw new ApiError(400, 'Item quantities must be whole numbers from 1 to 50.');
    }
    if (seen.has(String(productId))) throw new ApiError(400, 'Duplicate item in cart.');
    seen.add(String(productId));
    requested.push({ productId, quantity });
  }

  const table = await Table.findOne({ number: tableNum, active: true }).select('_id name number');
  if (!table) throw new ApiError(404, 'This table QR code is not recognized.');

  const products = await Product.find({
    _id: { $in: requested.map((x) => x.productId) },
    isDeleted: false,
  }).populate('category', 'status');

  const map = new Map(products.map((p) => [String(p._id), p]));
  const orderItems = [];
  let subtotal = 0;

  for (const { productId, quantity } of requested) {
    const product = map.get(String(productId));
    if (!product || product.status !== 'available' || !product.category || product.category.status !== 'active') {
      throw new ApiError(400, 'One of the items in your cart is no longer available.');
    }
    const total = round2(product.sellingPrice * quantity);
    subtotal = round2(subtotal + total);
    orderItems.push({
      product: product._id,
      name: product.name,
      price: product.sellingPrice,
      quantity,
      total,
    });
  }

  const settings = await BusinessSettings.getSettings();
  const tax = settings.taxEnabled ? round2((subtotal * settings.taxPercent) / 100) : 0;
  const amount = round2(subtotal + tax);

  const provider = getPaymentProvider();
  const transaction = await PaymentTransaction.create({
    clientRequestId: requestId,
    provider: provider.name,
    status: 'initiated',
    subtotal,
    discount: 0,
    tax,
    amount,
    currency: 'INR',
    items: orderItems,
    table: table._id,
    customerName: normalizedName || undefined,
    customerPhone: normalizedPhone || undefined,
    note: typeof note === 'string' ? note.trim() || undefined : undefined,
  });

  try {
    const payment = await provider.createPayment({
      transactionId: transaction._id.toString(),
      clientRequestId: requestId,
      amount,
      currency: 'INR',
      cafeName: settings.cafeName,
      tableNumber: table.number,
      customerName: normalizedName || undefined,
      customerPhone: normalizedPhone || undefined,
      items: orderItems,
    });

    transaction.status = 'processing';
    transaction.providerPaymentId = payment.providerPaymentId;
    transaction.providerPayload = {
      checkoutUrl: payment.checkoutUrl || null,
      clientToken: payment.clientToken || null,
    };
    await transaction.save();

    return res.status(201).json({
      success: true,
      data: {
        transactionId: transaction._id,
        status: transaction.status,
        provider: provider.name,
        checkoutUrl: payment.checkoutUrl || null,
        clientToken: payment.clientToken || null,
        providerPaymentId: payment.providerPaymentId || null,
      },
    });
  } catch (error) {
    transaction.status = 'failed';
    transaction.failureReason = error.message;
    await transaction.save();
    throw error;
  }
});

// GET /api/public/payments/:id/status
//
// This endpoint is display-only. A real adapter must obtain the status from
// the provider server-side. It never accepts a frontend "paid" flag.
const getPublicPaymentStatus = asyncHandler(async (req, res) => {
  const token = String(req.query.token || '').trim();
  if (!token) throw new ApiError(400, 'Payment token is required.');

  const transaction = await PaymentTransaction.findOne({
    _id: req.params.id,
    clientRequestId: token,
  });

  if (!transaction) throw new ApiError(404, 'Payment attempt not found.');

  const provider = getPaymentProvider();
  if (transaction.status === 'processing' || transaction.status === 'initiated') {
    const status = await provider.getPaymentStatus({
      providerPaymentId: transaction.providerPaymentId,
      transactionId: transaction._id.toString(),
    });

    if (status?.status === 'succeeded') {
      transaction.status = 'succeeded';
      transaction.providerPaymentId = status.providerPaymentId || transaction.providerPaymentId;
      transaction.verifiedAt = status.verifiedAt || new Date();
      await transaction.save();
      const order = await finalizeVerifiedPayment(transaction._id, status);
      if (order) pushNewOrderAlert(order).catch(() => {});
    } else if (status?.status && status.status !== transaction.status) {
      transaction.status = status.status;
      if (status.providerPaymentId) transaction.providerPaymentId = status.providerPaymentId;
      await transaction.save();
    }
  }

  res.json({
    success: true,
    data: {
      transactionId: transaction._id,
      status: transaction.status,
      orderId: transaction.orderId || null,
    },
  });
});


// POST /api/public/payments/:id/cancel
// Cancels only the payment transaction. It can never cancel/create a final
// Order belonging to another client because the clientRequestId is required.
const cancelPublicPayment = asyncHandler(async (req, res) => {
  const token = String(req.body?.token || req.query.token || '').trim();
  if (!token) throw new ApiError(400, 'Payment token is required.');

  const transaction = await PaymentTransaction.findOne({
    _id: req.params.id,
    clientRequestId: token,
  });
  if (!transaction) throw new ApiError(404, 'Payment attempt not found.');

  if (transaction.orderId || transaction.status === 'succeeded') {
    throw new ApiError(409, 'This payment has already succeeded and cannot be cancelled.');
  }

  if (['failed', 'cancelled', 'expired'].includes(transaction.status)) {
    return res.json({ success: true, message: 'Payment already ended.' });
  }

  transaction.status = 'cancelled';
  transaction.failureReason = 'Customer cancelled payment.';
  await transaction.save();

  res.json({ success: true, message: 'Payment cancelled.' });
});

module.exports = {
  createPublicPayment,
  getPublicPaymentStatus,
  cancelPublicPayment,
};
