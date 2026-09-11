const mongoose = require('mongoose');
const { PaymentTransaction, Order, Counter, Product, InventoryTransaction } = require('../models');

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
      const orderItems = transaction.items.map((item) => ({
        product: item.product,
        name: item.name,
        price: item.price,
        quantity: item.quantity,
        total: item.total,
        kotSentQuantity: item.quantity,
      }));

      const [order] = await Order.create(
        [{
          orderNumber,
          clientRequestId: transaction.clientRequestId,
          items: orderItems,
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
          status: 'completed',
          kitchenStatus: 'new',
          kots: [{
            kotNumber: 1,
            items: orderItems.map((item) => ({ product: item.product, name: item.name, quantity: item.quantity })),
            status: 'new',
            createdAt: new Date(),
          }],
          paymentInitiatedAt: transaction.createdAt,
        }],
        { session }
      );

      // QR online payments must enter the same inventory pipeline as staff bills.
      for (const line of orderItems) {
        const product = await Product.findOne({ _id: line.product, isDeleted: false, trackInventory: true }).session(session);
        if (!product) continue;
        const recipe = Array.isArray(product.recipe) ? product.recipe.filter((r) => r && r.ingredient && Number(r.quantity) > 0) : [];
        if (recipe.length) {
          for (const recipeLine of recipe) {
            const needed = Number(recipeLine.quantity) * line.quantity;
            const updated = await Product.findOneAndUpdate({ _id: recipeLine.ingredient, isDeleted: false, trackInventory: true, stock: { $gte: needed } }, { $inc: { stock: -needed } }, { new: true, session });
            if (!updated) throw new Error(`Insufficient ingredient for ${product.name}.`);
            await InventoryTransaction.create([{ product: updated._id, type: 'SALE', quantity: -needed, stockAfter: updated.stock, reason: `QR recipe sale #${order.orderNumber}`, order: order._id }], { session });
          }
        } else {
          const updated = await Product.findOneAndUpdate({ _id: product._id, stock: { $gte: line.quantity } }, { $inc: { stock: -line.quantity } }, { new: true, session });
          if (!updated) throw new Error(`Insufficient stock for ${product.name}.`);
          await InventoryTransaction.create([{ product: updated._id, type: 'SALE', quantity: -line.quantity, stockAfter: updated.stock, reason: `QR sale #${order.orderNumber}`, order: order._id }], { session });
        }
      }

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
