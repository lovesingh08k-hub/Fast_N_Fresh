const express = require('express');
const { listExpenses, createExpense, updateExpense, deleteExpense } = require('../controllers/expenseController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

// Expenses are sensitive business/financial data — admin only.
router.use(protect, authorize('admin'));

router.get('/', listExpenses);
router.post('/', createExpense);
router.put('/:id', updateExpense);
router.delete('/:id', deleteExpense);

module.exports = router;
