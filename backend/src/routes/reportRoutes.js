const express = require('express');
const {
  getSalesReport,
  getProductReport,
  getStaffReport,
  getCreditReport,
  getExpenseReport,
} = require('../controllers/reportController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

// Sales/product/staff-sales/expense reports remain admin-only, unchanged
// from the existing policy.
router.get('/sales', authorize('admin'), getSalesReport);
router.get('/products', authorize('admin'), getProductReport);
router.get('/staff', authorize('admin'), getStaffReport);
router.get('/expenses', authorize('admin'), getExpenseReport);

// Credit/UDHAR report: manager can also view outstanding balances/history,
// per the updated permission matrix — staff still cannot.
router.get('/credit', authorize('admin', 'manager'), getCreditReport);

module.exports = router;
