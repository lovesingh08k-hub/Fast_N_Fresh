const express = require('express');
const { protect, authorize } = require('../middleware/auth');
const { listKitchenOrders } = require('../controllers/kdsController');
const router = express.Router();
router.use(protect, authorize('admin', 'manager', 'staff'));
router.get('/orders', listKitchenOrders);
module.exports = router;
