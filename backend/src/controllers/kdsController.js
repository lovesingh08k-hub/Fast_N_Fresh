const { Order } = require('../models');
const { asyncHandler } = require('../utils/apiError');

const listKitchenOrders = asyncHandler(async (req, res) => {
  const orders = await Order.find({
    orderSource: 'qr',
    kitchenStatus: { $in: ['new', 'preparing', 'ready'] },
    status: { $ne: 'voided' },
  })
    .populate('table', 'name number')
    .populate('staff', 'name')
    .sort({ createdAt: 1 })
    .limit(100);
  res.json({ success: true, data: orders });
});
module.exports = { listKitchenOrders };
