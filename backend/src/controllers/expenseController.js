const { Expense } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

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
  const { title, category, amount, date, notes } = req.body;
  if (!title || !title.trim()) throw new ApiError(400, 'Expense title is required.');
  if (!amount || amount <= 0) throw new ApiError(400, 'A valid amount is required.');

  const expense = await Expense.create({
    title: title.trim(),
    category: category || 'Other',
    amount,
    date: date ? new Date(date) : new Date(),
    notes,
    recordedBy: req.user._id,
  });

  res.status(201).json({ success: true, data: expense });
});

const updateExpense = asyncHandler(async (req, res) => {
  const expense = await Expense.findById(req.params.id);
  if (!expense) throw new ApiError(404, 'Expense not found.');

  const editable = ['title', 'category', 'amount', 'date', 'notes'];
  editable.forEach((field) => {
    if (req.body[field] !== undefined) expense[field] = req.body[field];
  });
  await expense.save();

  res.json({ success: true, data: expense });
});

const deleteExpense = asyncHandler(async (req, res) => {
  const expense = await Expense.findByIdAndDelete(req.params.id);
  if (!expense) throw new ApiError(404, 'Expense not found.');
  res.json({ success: true, message: 'Expense deleted.' });
});

module.exports = { listExpenses, createExpense, updateExpense, deleteExpense };
