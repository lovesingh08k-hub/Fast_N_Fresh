const express = require('express');
const { protect, authorize } = require('../middleware/auth');
const { resetProductionOrderCounter } = require('../controllers/maintenanceController');

const router = express.Router();

// Admin-only, environment-key-gated one-off production maintenance action.
router.post('/order-counter/reset', protect, authorize('admin'), resetProductionOrderCounter);

module.exports = router;
