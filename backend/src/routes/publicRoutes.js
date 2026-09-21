const express = require('express');
const {
  getPublicMenu,
  getPublicTable,
  getPublicPaymentOptions,
  createPublicOrder,
  cancelPublicOrder,
  getPublicOrderStatus,
} = require('../controllers/publicController');
const { publicMenuLimiter, publicOrderLimiter } = require('../middleware/rateLimiters');
const { createPublicPayment, getPublicPaymentStatus, cancelPublicPayment } = require('../controllers/paymentController');
const { paymentWebhook } = require('../controllers/paymentWebhookController');

const router = express.Router();

// Public app-update metadata. This endpoint intentionally requires no login so
// an installed APK can check for a newer build before an authenticated API
// session is available. Configure the values in the backend environment.
router.get('/app-update', (req, res) => {
  const version = String(process.env.APP_UPDATE_VERSION || '').trim();
  const buildNumber = Number.parseInt(process.env.APP_UPDATE_BUILD || '0', 10) || 0;
  const downloadUrl = String(process.env.APP_UPDATE_DOWNLOAD_URL || '').trim();
  const notes = String(process.env.APP_UPDATE_NOTES || '').trim();
  const forceUpdate = String(process.env.APP_UPDATE_FORCE || '').toLowerCase() === 'true';

  res.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.json({
    enabled: Boolean(version && buildNumber > 0 && downloadUrl),
    version,
    buildNumber,
    downloadUrl,
    notes,
    forceUpdate,
  });
});

// Intentionally NOT behind `protect` — this is the customer-facing surface.
// Every handler here only ever reads customer-safe data or writes a new,
// server-priced order; nothing here can touch Admin/Staff data.
router.get('/menu', publicMenuLimiter, getPublicMenu);
router.get('/tables/:number', publicMenuLimiter, getPublicTable);
router.get('/payment-options', publicMenuLimiter, getPublicPaymentOptions);
router.post('/orders', publicOrderLimiter, createPublicOrder);
router.post('/orders/:id/cancel', publicOrderLimiter, cancelPublicOrder);
router.get('/orders/:id/status', publicMenuLimiter, getPublicOrderStatus);
router.post('/payments', publicOrderLimiter, createPublicPayment);
router.get('/payments/:id/status', publicMenuLimiter, getPublicPaymentStatus);
router.post('/payments/:id/cancel', publicOrderLimiter, cancelPublicPayment);
router.post('/payments/webhook', paymentWebhook);

module.exports = router;
