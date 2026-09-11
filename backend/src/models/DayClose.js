const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  businessDate: { type: String, required: true, unique: true, index: true },
  openingCash: { type: Number, required: true, min: 0, default: 0 },
  cashSales: { type: Number, default: 0, min: 0 },
  cashExpenses: { type: Number, default: 0, min: 0 },
  cashIn: { type: Number, default: 0, min: 0 },
  cashOut: { type: Number, default: 0, min: 0 },
  expectedCash: { type: Number, default: 0 },
  actualCash: { type: Number },
  difference: { type: Number },
  status: { type: String, enum: ['open','closed'], default: 'open' },
  openedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  closedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  closedAt: { type: Date },
  note: { type: String, trim: true },
}, { timestamps: true });
module.exports = mongoose.model('DayClose', schema);
