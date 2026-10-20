const { Expense, DayClose } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { businessDate } = require('../utils/dateRanges');

function parseExpenseDate(value) {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) throw new ApiError(400, 'A valid expense date is required.');
  return date;
}

// Closed days have reconciled cash totals, so their expenses are frozen.
async function assertDayOpenFor(date, message) {
  const closedDay = await DayClose.findOne({ businessDate: businessDate(date), status: 'closed' });
  if (closedDay) throw new ApiError(409, message);
}

const listExpenses = asyncHandler(async (req, res) => {
  const { from, to, category } = req.query;
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);

  const filter = {};
  if (category) filter.category = category;
  if (from || to) {
    filter.date = {};
    if (from) filter.date.$gte = new Date(from);
    if (to) filter.date.$lte = new Date(to);
  }

  const expenses = await Expense.find(filter)
    .populate('recordedBy', 'name')
    .sort({ date: -1 })
    .skip((page - 1) * limit)
    .limit(limit);
  const total = await Expense.countDocuments(filter);

  res.json({ success: true, data: expenses, pagination: { page, limit, total, pages: Math.ceil(total / limit) } });
});

const createExpense = asyncHandler(async (req, res) => {
  const { title, category, amount, date, notes, paymentMethod = 'CASH' } = req.body;
  const expenseDate = parseExpenseDate(date);
  await assertDayOpenFor(expenseDate, 'Business day is closed. Expenses cannot be added.');
  if (!['CASH', 'UPI', 'BANK', 'CARD'].includes(paymentMethod)) throw new ApiError(400, 'Invalid expense payment method.');
  if (typeof title !== 'string' || !title.trim()) throw new ApiError(400, 'Expense title is required.');
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) throw new ApiError(400, 'A valid amount is required.');

  const expense = await Expense.create({
    title: title.trim(),
    category: category || 'Other',
    amount: Math.round(value * 100) / 100,
    date: expenseDate,
    paymentMethod,
    notes,
    recordedBy: req.user._id,
  });

  res.status(201).json({ success: true, data: expense });
});

const updateExpense = asyncHandler(async (req, res) => {
  const expense = await Expense.findById(req.params.id);
  if (!expense) throw new ApiError(404, 'Expense not found.');

  await assertDayOpenFor(expense.date, 'Business day is closed. Expense cannot be changed.');
  if (req.body.date !== undefined) {
    // Moving an expense into a closed day would change that day's totals too.
    await assertDayOpenFor(parseExpenseDate(req.body.date), 'The target business day is closed. Expense cannot be moved there.');
  }
  if (req.body.amount !== undefined) {
    const value = Number(req.body.amount);
    if (!Number.isFinite(value) || value <= 0) throw new ApiError(400, 'A valid amount is required.');
  }

  const editable = ['title', 'category', 'amount', 'date', 'notes', 'paymentMethod'];
  editable.forEach((field) => {
    if (req.body[field] !== undefined) expense[field] = req.body[field];
  });
  await expense.save();

  res.json({ success: true, data: expense });
});

const deleteExpense = asyncHandler(async (req, res) => {
  const expense = await Expense.findById(req.params.id);
  if (!expense) throw new ApiError(404, 'Expense not found.');
  await assertDayOpenFor(expense.date, 'Business day is closed. Expense cannot be deleted.');
  await expense.deleteOne();
  res.json({ success: true, message: 'Expense deleted.' });
});

module.exports = { listExpenses, createExpense, updateExpense, deleteExpense };
