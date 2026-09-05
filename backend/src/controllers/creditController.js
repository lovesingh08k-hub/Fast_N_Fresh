const mongoose = require('mongoose');
const { Customer, CreditTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// Idempotency helper shared by grantCredit and recordCreditPayment: if a
// transaction with this clientRequestId already exists (this is a retry of
// a request that already succeeded — lost response, double-tap, etc.),
// return the same success payload instead of recording the payment/credit
// again.
async function findExistingTransactionResponse(clientRequestId, message = 'Credit recorded.') {
  const existing = await CreditTransaction.findOne({ clientRequestId }).populate('customer');
  if (!existing) return null;

  return {
    success: true,
    message,
    data: { customer: existing.customer, transaction: existing },
  };
}

// POST /api/credits/grant  { customerId, amount, note }
// Lets STAFF (as well as manager/admin) directly register a new UDHAR/credit
// transaction for a customer that isn't tied to a POS bill — e.g. goods
// given on credit outside the normal cart flow. This is intentionally the
// ONLY credit-related action exposed to staff: they can create a credit
// record but cannot view credit history/outstanding reports (see
// getCreditOverview/getRecentTransactions below, which are manager/admin
// only at the route level).
const grantCredit = asyncHandler(async (req, res) => {
  const { customerId, amount, note, clientRequestId } = req.body;
  if (!customerId) throw new ApiError(400, 'customerId is required.');

  const creditAmount = Number(amount);
  if (!creditAmount || creditAmount <= 0) throw new ApiError(400, 'A valid credit amount is required.');

  if (clientRequestId) {
    const existing = await findExistingTransactionResponse(clientRequestId);
    if (existing) return res.status(200).json(existing);
  }

  const session = await mongoose.startSession();
  let resultCustomer;
  let resultTransaction;

  try {
    await session.withTransaction(async () => {
      const customer = await Customer.findById(customerId).session(session);
      if (!customer) throw new ApiError(404, 'Customer not found.');

      customer.outstandingBalance = Math.round((customer.outstandingBalance + creditAmount) * 100) / 100;
      customer.totalPurchases = Math.round((customer.totalPurchases + creditAmount) * 100) / 100;
      await customer.save({ session });

      const [transaction] = await CreditTransaction.create(
        [
          {
            customer: customer._id,
            type: 'DEBIT',
            amount: creditAmount,
            method: 'ORDER',
            balanceAfter: customer.outstandingBalance,
            note: note || 'Credit given (not tied to a bill)',
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
      const existing = await findExistingTransactionResponse(clientRequestId, 'Credit recorded.');
      if (existing) return res.status(200).json(existing);
    }
    throw err;
  } finally {
    session.endSession();
  }

  res.status(201).json({ success: true, message: 'Credit recorded.', data: { customer: resultCustomer, transaction: resultTransaction } });
});

// GET /api/credits — overview of all customers with outstanding balances
const getCreditOverview = asyncHandler(async (req, res) => {
  const customersWithDue = await Customer.find({ outstandingBalance: { $gt: 0 }, status: 'active' }).sort({
    outstandingBalance: -1,
  });

  const totalOutstanding = customersWithDue.reduce((sum, c) => sum + c.outstandingBalance, 0);

  res.json({
    success: true,
    data: {
      totalOutstanding: Math.round(totalOutstanding * 100) / 100,
      customersWithDueCount: customersWithDue.length,
      customers: customersWithDue,
    },
  });
});

// GET /api/credits/transactions — recent ledger across all customers
const getRecentTransactions = asyncHandler(async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
  const transactions = await CreditTransaction.find()
    .populate('customer', 'name phone')
    .populate('order', 'orderNumber')
    .sort({ createdAt: -1 })
    .limit(limit);

  res.json({ success: true, data: transactions });
});

// POST /api/credits/payment  { customerId, amount, method, note }
// Thin wrapper matching the spec's flat /api/credits/payment endpoint;
// delegates to the same atomic logic used by /api/customers/:id/payment.
const recordCreditPayment = asyncHandler(async (req, res) => {
  const { customerId, amount, method, note, clientRequestId } = req.body;
  if (!customerId) throw new ApiError(400, 'customerId is required.');

  const paymentAmount = Number(amount);
  if (!paymentAmount || paymentAmount <= 0) throw new ApiError(400, 'A valid payment amount is required.');
  if (!['CASH', 'UPI'].includes(method)) throw new ApiError(400, 'Payment method must be CASH or UPI.');

  if (clientRequestId) {
    const existing = await findExistingTransactionResponse(clientRequestId, 'Payment recorded.');
    if (existing) return res.status(200).json(existing);
  }

  const session = await mongoose.startSession();
  let resultCustomer;
  let resultTransaction;

  try {
    await session.withTransaction(async () => {
      const customer = await Customer.findById(customerId).session(session);
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
      const existing = await findExistingTransactionResponse(clientRequestId, 'Payment recorded.');
      if (existing) return res.status(200).json(existing);
    }
    throw err;
  } finally {
    session.endSession();
  }

  res.json({ success: true, message: 'Payment recorded.', data: { customer: resultCustomer, transaction: resultTransaction } });
});

module.exports = { getCreditOverview, getRecentTransactions, recordCreditPayment, grantCredit };
