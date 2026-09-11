const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', required: true, unique: true },
  amount: { type: Number, required: true, min: 0 },
  method: { type: String, enum: ['CASH','UPI','CREDIT','MIXED'], required: true },
  reference: { type: String, trim: true },
  processedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  processedAt: { type: Date, default: Date.now },
  note: { type: String, trim: true },
}, { timestamps: true });
schema.index({ processedAt: -1 });
module.exports = mongoose.model('RefundTransaction', schema);
