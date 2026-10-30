const express = require('express');
const {
  createOrder,
  createKot,
  updateKitchenStatus,
  updateOpenOrderItems,
  checkoutOrder,
  updateQrOrderStatus,
  cancelOpenOrder,
  reassignAttendee,
  shiftOrderToTable,
  updateOpenOrderCustomer,
  updateOpenOrderNotes,
  listOrders,
  getOrder,
  refundOrder,
  startOpenOrder,
  quoteOrder,
  splitOpenOrder,
  mergeOpenOrders,
} = require('../controllers/orderController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.post('/', createOrder);
router.post('/quote', quoteOrder); // bill preview (GST, charges, round-off); saves nothing
router.post('/open', startOpenOrder); // admin/manager/staff can create bills (takeaway/delivery/quick dine-in)
router.get('/', listOrders); // staff see only their own (enforced in controller)
router.get('/:id', getOrder);

// Dine-in open-tab lifecycle
router.put('/:id/items', updateOpenOrderItems); // edit an unpaid table order's cart
router.post('/:id/checkout', checkoutOrder);
router.post('/:id/split', splitOpenOrder); // move some items to a new bill
router.post('/:id/merge', mergeOpenOrders); // join another open order into this one
router.patch('/:id/qr-status', updateQrOrderStatus); // legacy-compatible kitchen status
router.patch('/:id/kitchen-status', updateKitchenStatus);
router.post('/:id/kot', createKot); // finalize/bill an unpaid table order
router.delete('/:id', cancelOpenOrder); // cancel an unpaid table order before billing

// Handover — reassign which employee is attending this order (admin/manager only)
router.patch('/:id/attendee', authorize('admin', 'manager'), reassignAttendee);
router.patch('/:id/table', shiftOrderToTable);
router.patch('/:id/customer', updateOpenOrderCustomer);
router.patch('/:id/notes', updateOpenOrderNotes);

// Completed bills are permanent history: voiding (which removed a bill from
// the register) is disabled for everyone, including older app builds.
router.post('/:id/void', (req, res) => {
  res.status(403).json({ success: false, message: 'Bills cannot be deleted. Bill history is permanent.' });
});
router.post('/:id/refund', authorize('admin', 'manager'), refundOrder);

module.exports = router;
