const express = require('express');
const { getInventory, getProductHistory, adjustInventory } = require('../controllers/inventoryController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.get('/', getInventory);
router.get('/:productId/history', getProductHistory);
router.post('/adjust', authorize('admin'), adjustInventory); // inventory adjustments are admin-only

module.exports = router;
