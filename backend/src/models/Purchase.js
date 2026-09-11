const mongoose = require('mongoose');
const itemSchema = new mongoose.Schema({
  product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
  name: { type: String, required: true },
  quantity: { type: Number, required: true, min: 0.001 },
  unitCost: { type: Number, required: true, min: 0 },
  total: { type: Number, required: true, min: 0 },
}, { _id: false });
const schema = new mongoose.Schema({
  supplier: { type: String, trim: true, required: true },
  invoiceNumber: { type: String, trim: true },
  items: { type: [itemSchema], required: true },
  subtotal: { type: Number, required: true, min: 0 },
  tax: { type: Number, default: 0, min: 0 },
  total: { type: Number, required: true, min: 0 },
  paymentStatus: { type: String, enum: ['paid','unpaid','partial'], default: 'paid' },
  paidAmount: { type: Number, default: 0, min: 0 },
  date: { type: Date, default: Date.now },
  notes: { type: String, trim: true },
  recordedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
}, { timestamps: true });
schema.index({ date: -1 });
module.exports = mongoose.model('Purchase', schema);
