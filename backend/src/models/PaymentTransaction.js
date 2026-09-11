const mongoose = require('mongoose');

const paymentItemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
    name: { type: String, required: true },
    price: { type: Number, required: true, min: 0 },
    quantity: { type: Number, required: true, min: 1 },
    total: { type: Number, required: true, min: 0 },
  },
  { _id: false }
);

const paymentTransactionSchema = new mongoose.Schema(
  {
    clientRequestId: { type: String, required: true, unique: true, index: true },
    provider: { type: String, required: true, default: 'unconfigured' },
    providerPaymentId: { type: String, index: true, sparse: true },
    status: {
      type: String,
      enum: ['initiated', 'processing', 'succeeded', 'failed', 'cancelled', 'expired'],
      default: 'initiated',
      index: true,
    },
    subtotal: { type: Number, required: true, min: 0 },
    discount: { type: Number, default: 0, min: 0 },
    tax: { type: Number, default: 0, min: 0 },
    amount: { type: Number, required: true, min: 0 },
    currency: { type: String, default: 'INR' },
    items: { type: [paymentItemSchema], required: true, default: [] },
    table: { type: mongoose.Schema.Types.ObjectId, ref: 'Table', required: true },
    customerName: { type: String, trim: true },
    customerPhone: { type: String, trim: true },
    note: { type: String, trim: true },
    orderId: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', index: true, sparse: true },
    failureReason: { type: String, trim: true },
    providerPayload: { type: mongoose.Schema.Types.Mixed },
    verifiedAt: { type: Date },
  },
  { timestamps: true }
);

module.exports = mongoose.model('PaymentTransaction', paymentTransactionSchema);
