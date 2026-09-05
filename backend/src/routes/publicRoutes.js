const express = require('express');
const {
  getPublicMenu,
  getPublicTable,
  getPublicPaymentOptions,
  createPublicOrder,
  submitPublicUpiReference,
  cancelPublicOrder,
  getPublicOrderStatus,
} = require('../controllers/publicController');
const { publicMenuLimiter, publicOrderLimiter } = require('../middleware/rateLimiters');

const router = express.Router();

// Intentionally NOT behind `protect` — this is the customer-facing surface.
// Every handler here only ever reads customer-safe data or writes a new,
// server-priced order; nothing here can touch Admin/Staff data.
router.get('/menu', publicMenuLimiter, getPublicMenu);
router.get('/tables/:number', publicMenuLimiter, getPublicTable);
router.get('/payment-options', publicMenuLimiter, getPublicPaymentOptions);
router.post('/orders', publicOrderLimiter, createPublicOrder);
router.post('/orders/:id/upi-reference', publicOrderLimiter, submitPublicUpiReference);
router.post('/orders/:id/cancel', publicOrderLimiter, cancelPublicOrder);
router.get('/orders/:id/status', publicMenuLimiter, getPublicOrderStatus);

module.exports = router;
