const { Order } = require('../models');
const { asyncHandler } = require('../utils/apiError');

// A QR order paid at the counter may still need cooking, so it stays on the
// kitchen screen for a while, but not forever if nobody marked it served.
const PAID_ORDER_KITCHEN_MS = 2 * 60 * 60 * 1000;

const listKitchenOrders = asyncHandler(async (req, res) => {
  const orders = await Order.find({
    orderSource: 'qr',
    kitchenStatus: { $in: ['new', 'preparing', 'ready'] },
    $or: [
      { status: { $nin: ['voided', 'completed'] } },
      { status: 'completed', updatedAt: { $gte: new Date(Date.now() - PAID_ORDER_KITCHEN_MS) } },
    ],
  })
    .populate('table', 'name number')
    .populate('staff', 'name')
    .sort({ createdAt: 1 })
    .limit(100);
  res.json({ success: true, data: orders });
});
module.exports = { listKitchenOrders };
