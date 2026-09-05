const express = require('express');
const {
  createOrder,
  updateOpenOrderItems,
  checkoutOrder,
  updateQrOrderStatus,
  cancelOpenOrder,
  reassignAttendee,
  listOrders,
  getOrder,
  voidOrder,
} = require('../controllers/orderController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.post('/', createOrder); // admin/manager/staff can create bills (takeaway/delivery/quick dine-in)
router.get('/', listOrders); // staff see only their own (enforced in controller)
router.get('/:id', getOrder);

// Dine-in open-tab lifecycle
router.put('/:id/items', updateOpenOrderItems); // edit an unpaid table order's cart
router.post('/:id/checkout', checkoutOrder);
router.patch('/:id/qr-status', updateQrOrderStatus); // finalize/bill an unpaid table order
router.delete('/:id', cancelOpenOrder); // cancel an unpaid table order before billing

// Handover — reassign which employee is attending this order (admin/manager only)
router.patch('/:id/attendee', authorize('admin', 'manager'), reassignAttendee);

router.post('/:id/void', authorize('admin'), voidOrder);

module.exports = router;
