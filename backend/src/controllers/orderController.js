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

  const productIds = items.map((i) => i.productId || i.product);

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
    const productId = line.productId || line.product;
    const product = productMap.get(String(productId));
    const quantity = Number(line.quantity);

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
      product.stock < quantity
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
    const product = productMap.get(
      line.product.toString()
    );

    if (product.trackInventory) {
      product.stock -= line.quantity;

      await product.save({ session });

      await InventoryTransaction.create(
        [
          {
            product: product._id,
            type: 'SALE',
            quantity: -line.quantity,
            stockAfter: product.stock,
            reason: `Sold in bill #${order.orderNumber}`,
            order: order._id,
            recordedBy: req.user._id,
          },
        ],
        { session }
      );
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

  const normalizedClientRequestId = normalizeRequestId(clientRequestId);

  // Idempotency: if the app is retrying a checkout it already sent (lost
  // response after a Render cold-start timeout, a double-tap that slipped
  // past the frontend's submit-lock, etc.), return the original order
  // instead of creating a second bill/payment.
  if (normalizedClientRequestId) {
    const existing = await Order.findOne({ clientRequestId: normalizedClientRequestId })
      .populate('customer', 'name phone')
      .populate('staff', 'name role')
      .populate('table', 'name');

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
          },
        ],
        { session }
      );

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
        .populate('table', 'name');

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
    .populate('table', 'name');

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
      const productIds = items.map(
        (i) => i.productId || i.product
      );

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
        const product =
          productMap.get(
            String(
              line.productId ||
                line.product
            )
          );

        const quantity = Number(
          line.quantity
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

// POST /api/orders/:id/checkout
// Finalizes both normal open orders and QR orders.
const checkoutOrder =
  asyncHandler(async (req, res) => {
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

    if (paymentMethod === 'MIXED' && Number(upiPortion) > 0 && (!upiReference || !String(upiReference).trim())) {
      throw new ApiError(400, 'UPI reference / UTR is required for the UPI portion.');
    }

    if (paymentMethod === 'UPI' && (!upiReference || !String(upiReference).trim())) {
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
                    productId:
                      i.product,
                    quantity:
                      i.quantity,
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

    const filter = {};

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
      const asNumber =
        Number(search);

      if (!Number.isNaN(asNumber)) {
        filter.orderNumber =
          asNumber;
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
        );

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
    const allowed = ['preparing', 'ready'];

    if (!allowed.includes(status)) {
      throw new ApiError(400, 'Status must be preparing or ready.');
    }

    const order = await Order.findById(req.params.id);
    if (!order) throw new ApiError(404, 'Order not found.');
    if (!['open', 'preparing', 'ready'].includes(order.status)) {
      throw new ApiError(409, 'This order is already closed.');
    }

    const validTransition =
      (order.status === 'open' && status === 'preparing') ||
      (order.status === 'preparing' && status === 'ready');

    if (!validTransition) {
      throw new ApiError(409, `Cannot move order from ${order.status} to ${status}.`);
    }

    if (!order.staff) order.staff = req.user._id;
    const previousStatus = order.status;
    order.status = status;
    if (status === 'preparing') {
      order.estimatedReadyAt = new Date(Date.now() + 20 * 60 * 1000);
    }
    if (status === 'ready') order.estimatedReadyAt = new Date();
    await order.save();
    await audit(req, status === 'preparing' ? 'QR_ORDER_ACCEPTED' : 'QR_ORDER_READY', order, { from: previousStatus, to: status });

    const populated = await Order.findById(order._id)
      .populate('staff', 'name role')
      .populate('table', 'name number');

    res.json({ success: true, message: `Order marked ${status}.`, data: populated });
  });

// POST /api/orders/:id/void
// Reverses inventory and credit effects.
const voidOrder =
  asyncHandler(async (req, res) => {
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

          // Restock inventory.
          for (const line of order.items) {
            const product =
              await Product.findById(
                line.product
              ).session(session);

            if (
              product &&
              product.trackInventory
            ) {
              product.stock +=
                line.quantity;

              await product.save({
                session,
              });

              await InventoryTransaction.create(
                [
                  {
                    product:
                      product._id,
                    type:
                      'VOID_RESTOCK',
                    quantity:
                      line.quantity,
                    stockAfter:
                      product.stock,
                    reason:
                      `Void of bill #${order.orderNumber}`,
                    order:
                      order._id,
                    recordedBy:
                      req.user._id,
                  },
                ],
                { session }
              );
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
  startTableOrder,
  updateOpenOrderItems,
  checkoutOrder,
  updateQrOrderStatus,
  cancelOpenOrder,
  reassignAttendee,
  listOrders,
  getOrder,
  voidOrder,
};