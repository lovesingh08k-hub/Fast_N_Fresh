const { Customer, CreditTransaction, Order } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const mongoose = require('mongoose');
const { startSession } = require('../tenancy/context');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// GET /api/customers?search=&hasDue=true&page=&limit=
const listCustomers = asyncHandler(async (req, res) => {
  const { search, hasDue } = req.query;
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);

  const filter = { status: 'active' };
  if (hasDue === 'true') filter.outstandingBalance = { $gt: 0 };
  if (search) {
    // User text is matched literally; unescaped it could be an invalid or
    // catastrophically slow regex.
    const pattern = escapeRegex(String(search).trim());
    filter.$or = [
      { name: { $regex: pattern, $options: 'i' } },
      { phone: { $regex: pattern, $options: 'i' } },
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

// One customer per phone number. Only the last 10 digits count, so
// "+91 98765 43210" and "9876543210" are the same person.
async function assertPhoneIsFree(phone, exceptId) {
  const digits = String(phone).replace(/\D/g, '').slice(-10);
  if (digits.length < 6) return;
  const pattern = `${digits.split('').join('\\D*')}\\D*$`;
  const filter = { status: 'active', phone: { $regex: pattern } };
  if (exceptId) filter._id = { $ne: exceptId };
  const existing = await Customer.findOne(filter).select('name phone');
  if (existing) {
    throw new ApiError(409, `${phone} is already saved for ${existing.name}.`, { code: 'PHONE_EXISTS', customerId: existing._id });
  }
}

// GET /api/customers/directory -- everyone, kept small: the app stores it
// so customers can be found and picked while offline.
const listCustomerDirectory = asyncHandler(async (req, res) => {
  const customers = await Customer.find({ status: 'active' })
    .select('name phone address outstandingBalance totalPurchases status')
    .sort({ name: 1 })
    .lean();
  res.json({ success: true, data: customers });
});

const createCustomer = asyncHandler(async (req, res) => {
  const { name, phone, address, notes } = req.body;
  if (typeof name !== 'string' || !name.trim()) throw new ApiError(400, 'Customer name is required.');
  if (typeof phone !== 'string' || !phone.trim()) throw new ApiError(400, 'Phone number is required.');
  await assertPhoneIsFree(phone);

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

  if (req.body.phone !== undefined && req.body.phone !== customer.phone) {
    await assertPhoneIsFree(req.body.phone, customer._id);
  }

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
  const paymentAmount = round2(Number(amount));

  if (!Number.isFinite(paymentAmount) || paymentAmount <= 0) {
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

  const session = await startSession();
  let resultCustomer;
  let resultTransaction;

  try {
    await session.withTransaction(async () => {
      const customer = await Customer.findById(req.params.id).session(session);
      if (!customer) throw new ApiError(404, 'Customer not found.');

      if (paymentAmount > customer.outstandingBalance) {
        throw new ApiError(400, `Payment (₹${paymentAmount}) exceeds outstanding due (₹${customer.outstandingBalance}).`);
      }

      customer.outstandingBalance = round2(customer.outstandingBalance - paymentAmount);
      customer.totalPaid = round2(customer.totalPaid + paymentAmount);
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
  listCustomerDirectory,
  getCustomer,
  createCustomer,
  updateCustomer,
  deleteCustomer,
  recordPayment,
};
