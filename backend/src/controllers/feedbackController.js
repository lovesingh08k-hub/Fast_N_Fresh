const { Order, Feedback } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

const createFeedback = asyncHandler(async (req, res) => {
  const { orderId, token, rating, comment, customerName } = req.body || {};
  const score = Number(rating);
  if (!orderId || !token || !Number.isInteger(score) || score < 1 || score > 5) {
    throw new ApiError(400, 'Order, tracking token and a 1-5 rating are required.');
  }
  const order = await Order.findOne({ _id: orderId, clientRequestId: token, orderSource: 'qr' });
  if (!order) throw new ApiError(404, 'Order not found.');
  if (order.status !== 'completed') throw new ApiError(409, 'Feedback is available after the order is served.');
  const existing = await Feedback.findOne({ order: order._id });
  if (existing) throw new ApiError(409, 'Feedback already submitted for this order.');
  const feedback = await Feedback.create({ order: order._id, orderNumber: order.orderNumber, rating: score, comment: String(comment || '').trim(), customerName: String(customerName || '').trim(), token });
  res.status(201).json({ success: true, message: 'Thanks for your feedback!', data: feedback });
});

const listFeedback = asyncHandler(async (req, res) => {
  const feedback = await Feedback.find().sort({ createdAt: -1 }).limit(300);
  const summary = await Feedback.aggregate([{ $group: { _id: null, average: { $avg: '$rating' }, count: { $sum: 1 } } }]);
  res.json({ success: true, data: feedback, summary: summary[0] || { average: 0, count: 0 } });
});
module.exports = { createFeedback, listFeedback };
