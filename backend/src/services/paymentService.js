const mongoose = require('mongoose');
const { PaymentTransaction, Order, Counter } = require('../models');

async function finalizeVerifiedPayment(transactionId, providerData = {}) {
  const session = await mongoose.startSession();
  let finalOrder = null;

  try {
    await session.withTransaction(async () => {
      const transaction = await PaymentTransaction.findById(transactionId).session(session);
      if (!transaction) throw new Error('Payment transaction not found.');

      // Idempotent provider callbacks: one verified payment can create only
      // one final Order.
      if (transaction.orderId) {
        finalOrder = await Order.findById(transaction.orderId).session(session);
        return;
      }

      if (transaction.status !== 'succeeded') {
        throw new Error('Payment is not server-verified.');
      }

      const orderNumber = await Counter.getNextSequence('orderNumber');
      const [order] = await Order.create(
        [{
          orderNumber,
          clientRequestId: transaction.clientRequestId,
          items: transaction.items,
          orderType: 'dine_in',
          orderSource: 'qr',
          table: transaction.table,
          qrCustomerContact: {
            name: transaction.customerName || undefined,
            phone: transaction.customerPhone || undefined,
          },
          subtotal: transaction.subtotal,
          discount: transaction.discount,
          tax: transaction.tax,
          grandTotal: transaction.amount,
          paymentMethod: 'UPI',
          paymentStatus: 'paid',
          paymentBreakdown: { cash: 0, upi: transaction.amount, credit: 0 },
          notes: transaction.note,
          status: 'open',
          paymentInitiatedAt: transaction.createdAt,
        }],
        { session }
      );

      transaction.orderId = order._id;
      transaction.status = 'succeeded';
      transaction.verifiedAt = transaction.verifiedAt || new Date();
      transaction.providerPayload = {
        ...(transaction.providerPayload || {}),
        verification: providerData,
      };
      await transaction.save({ session });
      finalOrder = order;
    });
  } finally {
    await session.endSession();
  }

  return finalOrder;
}

module.exports = { finalizeVerifiedPayment };
