const { Customer, CreditTransaction, Order } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const mongoose = require('mongoose');

// GET /api/customers?search=&hasDue=true&page=&limit=
const listCustomers = asyncHandler(async (req, res) => {
  const { search, hasDue } = req.query;
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);

  const filter = { status: 'active' };
  if (hasDue === 'true') filter.outstandingBalance = { $gt: 0 };
  if (search) {
    filter.$or = [
      { name: { $regex: search, $options: 'i' } },
      { phone: { $regex: search, $options: 'i' } },
    ];
  }

  const customers = await Customer.find(filter)
    .sort({ outstandingBalance: -1, name: 1 })
    .skip((page - 1) * limit)
    .limit(limit);

  const total = await Customer.countDocuments(filter);

  res.json({
    success: true,
    data: customers,
    pagination: { page, limit, total, pages: Math.ceil(total / limit) },
  });
});

const getCustomer = asyncHandler(async (req, res) => {
  const customer = await Customer.findById(req.params.id);
  if (!customer) throw new ApiError(404, 'Customer not found.');

  // Staff can look up a customer (needed for billing/credit-granting) but
  // must not see the credit/UDHAR transaction ledger — that's manager/admin
  // only. Enforced here, not just hidden in the UI.
  if (req.user.role === 'staff') {
    return res.json({ success: true, data: { customer, transactions: [] } });
  }

  const transactions = await CreditTransaction.find({ customer: customer._id })
    .sort({ createdAt: -1 })
    .limit(100)
    .populate('order', 'orderNumber');

  res.json({ success: true, data: { customer, transactions } });
});

const createCustomer = asyncHandler(async (req, res) => {
  const { name, phone, address, notes } = req.body;
  if (!name || !name.trim()) throw new ApiError(400, 'Customer name is required.');
  if (!phone || !phone.trim()) throw new ApiError(400, 'Phone number is required.');

  const customer = await Customer.create({
    name: name.trim(),
    phone: phone.trim(),
    address: address?.trim(),
    notes: notes?.trim(),
    createdBy: req.user._id,
  });

  res.status(201).json({ success: true, data: customer });
});

const updateCustomer = asyncHandler(async (req, res) => {
  const customer = await Customer.findById(req.params.id);
  if (!customer) throw new ApiError(404, 'Customer not found.');

  const editable = ['name', 'phone', 'address', 'notes'];
  editable.forEach((field) => {
    if (req.body[field] !== undefined) customer[field] = req.body[field];
  });

  await customer.save();
  res.json({ success: true, data: customer });
});

// Admin-only delete (soft)
const deleteCustomer = asyncHandler(async (req, res) => {
  const customer = await Customer.findById(req.params.id);
  if (!customer) throw new ApiError(404, 'Customer not found.');
  if (customer.outstandingBalance > 0) {
    throw new ApiError(409, 'Cannot delete a customer with outstanding UDHAR balance.');
  }
  customer.status = 'inactive';
  await customer.save();
  res.json({ success: true, message: 'Customer removed.' });
});

// POST /api/customers/:id/payment  { amount, method, note }
// Records a UDHAR payment and atomically decreases the customer's outstanding balance.
const recordPayment = asyncHandler(async (req, res) => {
  const { amount, method, note, clientRequestId } = req.body;
  const paymentAmount = Number(amount);

  if (!paymentAmount || paymentAmount <= 0) {
    throw new ApiError(400, 'A valid payment amount is required.');
  }
  if (!['CASH', 'UPI'].includes(method)) {
    throw new ApiError(400, 'Payment method must be CASH or UPI.');
  }

  // Idempotency: a retried request (lost response, double-tap) with the
  // same clientRequestId returns the already-recorded payment instead of
  // deducting the customer's balance a second time.
  if (clientRequestId) {
    const existing = await CreditTransaction.findOne({ clientRequestId }).populate('customer');
    if (existing) {
      return res.status(200).json({
        success: true,
        message: 'Payment recorded.',
        data: { customer: existing.customer, transaction: existing },
      });
    }
  }

  const session = await mongoose.startSession();
  let resultCustomer;
  let resultTransaction;

  try {
    await session.withTransaction(async () => {
      const customer = await Customer.findById(req.params.id).session(session);
      if (!customer) throw new ApiError(404, 'Customer not found.');

      if (paymentAmount > customer.outstandingBalance) {
        throw new ApiError(400, `Payment (₹${paymentAmount}) exceeds outstanding due (₹${customer.outstandingBalance}).`);
      }

      customer.outstandingBalance -= paymentAmount;
      customer.totalPaid += paymentAmount;
      await customer.save({ session });

      const [transaction] = await CreditTransaction.create(
        [
          {
            customer: customer._id,
            type: 'PAID',
            amount: paymentAmount,
            method,
            balanceAfter: customer.outstandingBalance,
            note,
            recordedBy: req.user._id,
            clientRequestId: clientRequestId || undefined,
          },
        ],
        { session }
      );

      resultCustomer = customer;
      resultTransaction = transaction;
    });
  } catch (err) {
    if (err.code === 11000 && clientRequestId && err.keyPattern?.clientRequestId) {
      const existing = await CreditTransaction.findOne({ clientRequestId }).populate('customer');
      if (existing) {
        return res.status(200).json({
          success: true,
          message: 'Payment recorded.',
          data: { customer: existing.customer, transaction: existing },
        });
      }
    }
    throw err;
  } finally {
    session.endSession();
  }

  res.json({
    success: true,
    message: 'Payment recorded.',
    data: { customer: resultCustomer, transaction: resultTransaction },
  });
});

module.exports = {
  listCustomers,
  getCustomer,
  createCustomer,
  updateCustomer,
  deleteCustomer,
  recordPayment,
};
