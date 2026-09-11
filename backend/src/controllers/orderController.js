const mongoose = require('mongoose');
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
  RefundTransaction,
  DayClose,
} = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

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

// Shared pricing and validation logic used by direct bills and QR/open-order checkout.
async function priceAndValidate({
  items,
  discount,
  paymentMethod,
  amountReceived,
  customerId,
  cashPortion,
  upiPortion,
  creditPortion,
  session,
}) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new ApiError(400, 'Cart is empty. Add at least one item.');
  }

  if (!['CASH', 'UPI', 'CREDIT', 'MIXED'].includes(paymentMethod)) {
    throw new ApiError(400, 'A valid payment method is required.');
  }

  const productIds = items
    .filter((i) => !(i.quickItem && String(i.quickItem.name || '').trim()))
    .map((i) => i.productId || i.product)
    .filter(Boolean);

  const products = await Product.find({
    _id: { $in: productIds },
    isDeleted: false,
  }).session(session);

  const productMap = new Map(
    products.map((p) => [p._id.toString(), p])
  );

  const orderItems = [];
  let subtotal = 0;

  for (const line of items) {
    const quantity = Number(line.quantity);
    const quick = line.quickItem;
    const isQuickItem = quick && String(quick.name || '').trim();

    if (isQuickItem) {
      const quickName = String(quick.name).trim();
      const quickPrice = Number(quick.price);
      if (!quickName || !Number.isFinite(quickPrice) || quickPrice < 0) {
        throw new ApiError(400, 'Invalid Quick Item name or price.');
      }
      if (!Number.isFinite(quantity) || quantity < 1) {
        throw new ApiError(400, `Invalid quantity for ${quickName}.`);
      }
      const lineTotal = round2(quickPrice * quantity);
      subtotal = round2(subtotal + lineTotal);
      orderItems.push({
        name: quickName,
        price: quickPrice,
        quantity,
        total: lineTotal,
        quickItem: { name: quickName, price: quickPrice },
      });
      continue;
    }

    const productId = line.productId || line.product;
    const product = productMap.get(String(productId));

    if (!product) {
      throw new ApiError(400, 'Product not found or unavailable.');
    }

    if (product.status !== 'available') {
      throw new ApiError(
        400,
        `${product.name} is currently unavailable.`
      );
    }

    if (!Number.isFinite(quantity) || quantity < 1) {
      throw new ApiError(
        400,
        `Invalid quantity for ${product.name}.`
      );
    }

    if (
      product.trackInventory &&
      product.stock < quantity && !(Array.isArray(product.recipe) && product.recipe.length)
    ) {
      throw new ApiError(
        400,
        `Insufficient stock for ${product.name}. Available: ${product.stock}.`
      );
    }

    const lineTotal = round2(
      product.sellingPrice * quantity
    );

    subtotal = round2(subtotal + lineTotal);

    orderItems.push({
      product: product._id,
      name: product.name,
      price: product.sellingPrice,
      quantity,
      total: lineTotal,
    });
  }

  const safeDiscount = Math.max(
    0,
    Math.min(Number(discount) || 0, subtotal)
  );

  // Tax is computed from live BusinessSettings (not trusted from the
  // client) on the post-discount amount, mirroring how discount itself is
  // applied before totalling.
  const settings = await BusinessSettings.getSettings(session);
  const taxableAmount = round2(subtotal - safeDiscount);
  const tax = settings.taxEnabled
    ? round2((taxableAmount * settings.taxPercent) / 100)
    : 0;

  const grandTotal = round2(
    taxableAmount + tax
  );

  let paymentBreakdown = {
    cash: 0,
    upi: 0,
    credit: 0,
  };

  if (paymentMethod === 'CASH') {
    paymentBreakdown.cash = grandTotal;
  }

  if (paymentMethod === 'UPI') {
    paymentBreakdown.upi = grandTotal;
  }

  if (paymentMethod === 'CREDIT') {
    paymentBreakdown.credit = grandTotal;
  }

  if (paymentMethod === 'MIXED') {
    paymentBreakdown = {
      cash: round2(Number(cashPortion) || 0),
      upi: round2(Number(upiPortion) || 0),
      credit: round2(Number(creditPortion) || 0),
    };

    const sum = round2(
      paymentBreakdown.cash +
        paymentBreakdown.upi +
        paymentBreakdown.credit
    );

    if (sum !== grandTotal) {
      throw new ApiError(
        400,
        `Mixed payment split (Rs ${sum}) does not equal grand total (Rs ${grandTotal}).`
      );
    }
  }

  let changeReturned = 0;

  if (
    paymentMethod === 'CASH' &&
    amountReceived !== undefined
  ) {
    const received = Number(amountReceived);

    if (received < grandTotal) {
      throw new ApiError(
        400,
        'Amount received is less than the grand total.'
      );
    }

    changeReturned = round2(
      received - grandTotal
    );
  }

  let customer = null;

  if (customerId) {
    customer = await Customer.findById(customerId).session(
      session
    );

    if (!customer) {
      throw new ApiError(
        404,
        'Selected customer not found.'
      );
    }
  }

  if (
    paymentBreakdown.credit > 0 &&
    !customer
  ) {
    throw new ApiError(
      400,
      'A customer must be selected for the credit portion of this bill.'
    );
  }

  return {
    orderItems,
    productMap,
    subtotal,
    safeDiscount,
    tax,
    grandTotal,
    paymentBreakdown,
    changeReturned,
    customer,
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
    const recipe = Array.isArray(product.recipe) ? product.recipe.filter(r => r && r.ingredient && Number(r.quantity) > 0) : [];
    if (recipe.length) {
      for (const recipeLine of recipe) {
        const ingredient = await Product.findOne({_id: recipeLine.ingredient, isDeleted:false, trackInventory:true}).session(session);
        if (!ingredient) throw new ApiError(400, `Recipe ingredient missing for ${product.name}.`);
        const needed = Number(recipeLine.quantity) * line.quantity;
        const updated = await Product.findOneAndUpdate({_id:ingredient._id,stock:{$gte:needed}},{$inc:{stock:-needed}},{new:true,session});
        if (!updated) throw new ApiError(400, `Insufficient ingredient ${ingredient.name} for ${product.name}.`);
        await InventoryTransaction.create([{product:ingredient._id,type:'SALE',quantity:-needed,stockAfter:updated.stock,reason:`Recipe for ${line.quantity} x ${product.name} in bill #${order.orderNumber}`,order:order._id,recordedBy:req.user._id}],{session});
      }
    } else {
      const updated = await Product.findOneAndUpdate({_id:product._id,stock:{$gte:line.quantity}},{$inc:{stock:-line.quantity}},{new:true,session});
      if (!updated) throw new ApiError(400, `Insufficient stock for ${product.name}.`);
      await InventoryTransaction.create([{product:product._id,type:'SALE',quantity:-line.quantity,stockAfter:updated.stock,reason:`Sold in bill #${order.orderNumber}`,order:order._id,recordedBy:req.user._id}],{session});
    }
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
  for (const line of nextItems) {
    const previousSent = sentByKey.get(orderLineKey(line)) || 0;
    if (previousSent > line.quantity) {
      throw new ApiError(409, `Cannot reduce ${line.name} below the quantity already sent to kitchen.`);
    }
    line.kotSentQuantity = previousSent;
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

  const session = await mongoose.startSession();

  let savedOrder;
  let updatedCustomer = null;

  try {
    await session.withTransaction(async () => {
      const priced = await priceAndValidate({
        items,
        discount,
        paymentMethod,
        amountReceived,
        customerId,
        cashPortion,
        upiPortion,
        creditPortion,
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
          'orderNumber'
        );

      const [order] = await Order.create(
        [
          {
            orderNumber,
            clientRequestId: normalizedClientRequestId,
            items: priced.orderItems,
            subtotal: priced.subtotal,
            discount: priced.safeDiscount,
            tax: priced.tax,
            grandTotal: priced.grandTotal,
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
          tableCustomerLabel ||
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
    } = req.body;

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

    const orderItems = [];
    let subtotal = 0;

    if (items.length > 0) {
      const productIds = items
        .filter((i) => !(i.quickItem && String(i.quickItem.name || '').trim()))
        .map((i) => i.productId || i.product)
        .filter(Boolean);

      const products =
        await Product.find({
          _id: { $in: productIds },
          isDeleted: false,
        });

      const productMap = new Map(
        products.map((p) => [
          p._id.toString(),
          p,
        ])
      );

      for (const line of items) {
        const quick = line.quickItem;
        const isQuickItem = quick && String(quick.name || '').trim();
        const quantity = Number(line.quantity);

        if (isQuickItem) {
          const quickName = String(quick.name).trim();
          const quickPrice = Number(quick.price);
          if (!quickName || !Number.isFinite(quickPrice) || quickPrice < 0 || !Number.isFinite(quantity) || quantity < 1) {
            throw new ApiError(400, 'Invalid Quick Item.');
          }
          const lineTotal = round2(quickPrice * quantity);
          subtotal = round2(subtotal + lineTotal);
          orderItems.push({
            name: quickName,
            price: quickPrice,
            quantity,
            total: lineTotal,
            quickItem: { name: quickName, price: quickPrice },
          });
          continue;
        }

        const product =
          productMap.get(
            String(
              line.productId ||
                line.product
            )
          );

        if (!product) {
          throw new ApiError(
            400,
            'Product not found or unavailable.'
          );
        }

        if (
          product.status !==
          'available'
        ) {
          throw new ApiError(
            400,
            `${product.name} is currently unavailable.`
          );
        }

        if (
          !Number.isFinite(quantity) ||
          quantity < 1
        ) {
          throw new ApiError(
            400,
            `Invalid quantity for ${product.name}.`
          );
        }

        const lineTotal = round2(
          product.sellingPrice *
            quantity
        );

        subtotal = round2(
          subtotal + lineTotal
        );

        orderItems.push({
          product: product._id,
          name: product.name,
          price: product.sellingPrice,
          quantity,
          total: lineTotal,
        });
      }
    }

    const safeDiscount =
      Math.max(
        0,
        Math.min(
          Number(discount) || 0,
          subtotal
        )
      );

    preserveKotSentQuantities(order.items, orderItems);
    order.items = orderItems;
    order.subtotal = subtotal;
    order.discount = safeDiscount;
    order.grandTotal = round2(
      subtotal - safeDiscount
    );

    if (notes !== undefined) {
      order.notes = notes;
    }

    if (customerId !== undefined) {
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

  const session = await mongoose.startSession();
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
      await mongoose.startSession();

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
                    ...(i.quickItem
                      ? { quickItem: i.quickItem }
                      : {}),
                  })
                ),
              discount:
                discount !== undefined
                  ? discount
                  : order.discount,
              paymentMethod,
              amountReceived,
              customerId:
                effectiveCustomerId,
              cashPortion,
              upiPortion,
              creditPortion,
              session,
            });

          order.items =
            priced.orderItems;

          order.subtotal =
            priced.subtotal;

          order.discount =
            priced.safeDiscount;

          order.tax =
            priced.tax;

          order.grandTotal =
            priced.grandTotal;

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

    order.status = 'voided';
    order.paymentStatus = 'cancelled';
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

    const now = new Date();

    if (order.staff) {
      order.attendedByHistory.push({
        user: order.staff,
        from: order.createdAt,
        to: now,
      });
    }

    order.staff = userId;

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
    if (status) {
      filter.status = status;
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
          new Date(from);
      }

      if (to) {
        filter.createdAt.$lte =
          new Date(to);
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

      filter.$or = [
        ...(Number.isFinite(asNumber) ? [{ orderNumber: asNumber }] : []),
        ...(matchingCustomers.length ? [{ customer: { $in: matchingCustomers.map((c) => c._id) } }] : []),
      ];
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
  const paidCash = round2(order.paymentBreakdown?.cash || 0);
  const paidUpi = round2(order.paymentBreakdown?.upi || 0);
  const paidCredit = round2(order.paymentBreakdown?.credit || 0);
  const paidAmount = round2(paidCash + paidUpi + paidCredit);
  const amount = round2(Number(req.body.amount ?? paidAmount));
  if (amount <= 0 || amount > paidAmount) throw new ApiError(400, 'Refund cannot exceed the amount actually paid.');
  const method = req.body.method || (order.paymentMethod === 'MIXED' ? 'MIXED' : order.paymentMethod);
  if (!['CASH','UPI','CREDIT','MIXED'].includes(method)) throw new ApiError(400, 'Invalid refund method.');
  if (method === 'CASH' && amount > paidCash) throw new ApiError(400, 'Cash refund exceeds cash paid.');
  if (method === 'UPI' && amount > paidUpi) throw new ApiError(400, 'UPI refund exceeds UPI paid.');
  if (method === 'CREDIT' && amount > paidCredit) throw new ApiError(400, 'Credit refund exceeds credit paid.');
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
      await mongoose.startSession();

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

          if (
            order.status === 'open'
          ) {
            throw new ApiError(
              409,
              'This order has not been billed yet - cancel it instead of voiding.'
            );
          }

          // Reverse the exact inventory movement made at sale time. Recipe
          // products consume ingredients, not finished-product stock.
          for (const line of order.items) {
            const product = await Product.findById(line.product).session(session);
            if (!product || !product.trackInventory) continue;
            const recipe = Array.isArray(product.recipe) ? product.recipe.filter((r) => r && r.ingredient && Number(r.quantity) > 0) : [];
            if (recipe.length) {
              for (const recipeLine of recipe) {
                const qty = Number(recipeLine.quantity) * line.quantity;
                const ingredient = await Product.findById(recipeLine.ingredient).session(session);
                if (!ingredient) throw new ApiError(409, `Recipe ingredient is missing for ${product.name}; void aborted.`);
                ingredient.stock += qty;
                await ingredient.save({ session });
                await InventoryTransaction.create([{ product: ingredient._id, type: 'VOID_RESTOCK', quantity: qty, stockAfter: ingredient.stock, reason: `Recipe reversal for bill #${order.orderNumber}`, order: order._id, recordedBy: req.user._id }], { session });
              }
            } else {
              product.stock += line.quantity;
              await product.save({ session });
              await InventoryTransaction.create([{ product: product._id, type: 'VOID_RESTOCK', quantity: line.quantity, stockAfter: product.stock, reason: `Void of bill #${order.orderNumber}`, order: order._id, recordedBy: req.user._id }], { session });
            }
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

              customer.totalPurchases =
                round2(
                  customer.totalPurchases -
                    order.grandTotal
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

module.exports = {
  createOrder,
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
