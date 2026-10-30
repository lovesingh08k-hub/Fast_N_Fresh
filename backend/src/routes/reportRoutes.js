const express = require('express');
const {
  getSalesReport,
  getProductReport,
  getStaffReport,
  getCreditReport,
  getExpenseReport,
  getTaxReport,
  getDayEndReport,
} = require('../controllers/reportController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

// Sales/product/staff-sales/expense reports remain admin-only, unchanged
// from the existing policy.
router.get('/sales', authorize('admin', 'manager'), getSalesReport);
router.get('/products', authorize('admin', 'manager'), getProductReport);
router.get('/staff', authorize('admin', 'manager'), getStaffReport);
router.get('/expenses', authorize('admin', 'manager'), getExpenseReport);
router.get('/tax', authorize('admin', 'manager'), getTaxReport); // GST summary per rate
router.get('/day-end', authorize('admin', 'manager'), getDayEndReport); // Z report

// Credit/UDHAR report: manager can also view outstanding balances/history,
// per the updated permission matrix — staff still cannot.
router.get('/credit', authorize('admin', 'manager'), getCreditReport);

module.exports = router;
