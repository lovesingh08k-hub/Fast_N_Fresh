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
  voidOrder,
  refundOrder,
  startOpenOrder,
} = require('../controllers/orderController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.post('/', createOrder);
router.post('/open', startOpenOrder); // admin/manager/staff can create bills (takeaway/delivery/quick dine-in)
router.get('/', listOrders); // staff see only their own (enforced in controller)
router.get('/:id', getOrder);

// Dine-in open-tab lifecycle
router.put('/:id/items', updateOpenOrderItems); // edit an unpaid table order's cart
router.post('/:id/checkout', checkoutOrder);
router.patch('/:id/qr-status', updateQrOrderStatus); // legacy-compatible kitchen status
router.patch('/:id/kitchen-status', updateKitchenStatus);
router.post('/:id/kot', createKot); // finalize/bill an unpaid table order
router.delete('/:id', cancelOpenOrder); // cancel an unpaid table order before billing

// Handover — reassign which employee is attending this order (admin/manager only)
router.patch('/:id/attendee', authorize('admin', 'manager'), reassignAttendee);
router.patch('/:id/table', shiftOrderToTable);
router.patch('/:id/customer', updateOpenOrderCustomer);
router.patch('/:id/notes', updateOpenOrderNotes);

router.post('/:id/void', authorize('admin'), voidOrder);
router.post('/:id/refund', authorize('admin', 'manager'), refundOrder);

module.exports = router;
