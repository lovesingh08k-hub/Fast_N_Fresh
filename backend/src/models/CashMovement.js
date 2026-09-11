const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  type: { type: String, enum: ['OPENING','IN','OUT','EXPENSE','SALE'], required: true },
  amount: { type: Number, required: true, min: 0 },
  reason: { type: String, trim: true },
  reference: { type: String, trim: true },
  recordedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  businessDate: { type: String, required: true, index: true },
}, { timestamps: true });
schema.index({ businessDate: 1, createdAt: -1 });
module.exports = mongoose.model('CashMovement', schema);
