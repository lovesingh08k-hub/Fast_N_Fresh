const express = require('express');
const { listTables, getTable, createTable, updateTable, deleteTable, getTableQr } = require('../controllers/tableController');
const { startTableOrder } = require('../controllers/orderController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

// Everyone (including staff) can view tables and select one to start an order.
router.get('/', listTables);
router.get('/:id', getTable);
router.get('/:id/qr', authorize('admin', 'manager'), getTableQr);

// Managing the table list itself (add/edit/deactivate) is admin + manager only.
router.post('/', authorize('admin', 'manager'), createTable);
router.put('/:id', authorize('admin', 'manager'), updateTable);
router.delete('/:id', authorize('admin', 'manager'), deleteTable);

// Starting a new customer/order tab on a table — any authenticated staff.
router.post('/:tableId/orders', startTableOrder);

module.exports = router;
