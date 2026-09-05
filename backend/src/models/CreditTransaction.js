const mongoose = require('mongoose');

// Ledger of every UDHAR event: a new credit sale (DEBIT) or a payment
// received against outstanding due (CREDIT/PAID).
const creditTransactionSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer', required: true, index: true },
    type: { type: String, enum: ['DEBIT', 'PAID'], required: true }, // DEBIT = new UDHAR, PAID = payment received
    amount: { type: Number, required: true, min: 0 },
    method: { type: String, enum: ['CASH', 'UPI', 'ORDER'], required: true }, // ORDER = created via a credit bill
    order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order' },
    balanceAfter: { type: Number, required: true },
    note: { type: String, trim: true },
    recordedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    // Idempotency guard for UDHAR payment collection / credit grants, same
    // pattern as Order.clientRequestId — protects against a retried request
    // (dropped response, double-tap) recording the same cash/UPI payment or
    // credit grant twice.
    clientRequestId: { type: String, index: { unique: true, sparse: true } },
  },
  { timestamps: true }
);

creditTransactionSchema.index({ customer: 1, createdAt: -1 });

module.exports = mongoose.model('CreditTransaction', creditTransactionSchema);
