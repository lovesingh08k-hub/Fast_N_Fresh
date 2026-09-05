const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    phone: { type: String, required: true, trim: true, index: true },
    address: { type: String, trim: true },
    notes: { type: String, trim: true },
    totalPurchases: { type: Number, default: 0 }, // lifetime billed amount
    totalPaid: { type: Number, default: 0 }, // lifetime payments received
    outstandingBalance: { type: Number, default: 0, index: true }, // current UDHAR due
    status: { type: String, enum: ['active', 'inactive'], default: 'active' },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

customerSchema.index({ name: 'text', phone: 'text' });

module.exports = mongoose.model('Customer', customerSchema);
