const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
  quantity: { type: Number, required: true, min: 0.001 },
  reason: { type: String, enum: ['Burnt','Expired','Spoilage','Wrong Preparation','Customer Return','Other'], default: 'Other' },
  notes: { type: String, trim: true },
  recordedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
}, { timestamps: true });
schema.index({ createdAt: -1 });
module.exports = mongoose.model('Wastage', schema);
