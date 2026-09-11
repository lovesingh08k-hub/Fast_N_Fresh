const { PaymentTransaction } = require('../models');
const { getPaymentProvider } = require('../services/paymentProvider');
const { finalizeVerifiedPayment } = require('../services/paymentService');
const { pushNewOrderAlert } = require('../utils/push');

async function paymentWebhook(req, res) {
  const provider = getPaymentProvider();

  try {
    const verified = await provider.verifyWebhook({
      headers: req.headers,
      body: req.body,
      rawBody: req.rawBody,
    });

    if (!verified || !verified.transactionId || verified.status !== 'succeeded') {
      return res.status(400).json({ success: false, message: 'Unverified payment callback.' });
    }

    const transaction = await PaymentTransaction.findById(verified.transactionId);
    if (!transaction) {
      return res.status(404).json({ success: false, message: 'Payment transaction not found.' });
    }

    if (transaction.status === 'succeeded' && transaction.orderId) {
      return res.json({ success: true, orderId: transaction.orderId, idempotent: true });
    }

    transaction.status = 'succeeded';
    transaction.providerPaymentId = verified.providerPaymentId || transaction.providerPaymentId;
    transaction.verifiedAt = new Date();
    await transaction.save();

    const order = await finalizeVerifiedPayment(transaction._id, verified);
    if (order) pushNewOrderAlert(order).catch(() => {});
    return res.json({ success: true, orderId: order?._id || null });
  } catch (error) {
    const status = Number(error.statusCode) || 503;
    return res.status(status).json({
      success: false,
      message: error.message || 'Payment verification failed.',
    });
  }
}

module.exports = { paymentWebhook };
