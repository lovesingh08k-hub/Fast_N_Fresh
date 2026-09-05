const mongoose = require('mongoose');

const feedbackSchema = new mongoose.Schema({
  // No `index: true` here — the unique index declared below
  // (feedbackSchema.index({ order: 1 }, { unique: true })) already covers
  // lookups by `order` AND enforces one feedback per order. Declaring both
  // produced Mongoose's "Duplicate schema index on {"order":1}" warning.
  order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', required: true },
  orderNumber: { type: Number, required: true },
  rating: { type: Number, required: true, min: 1, max: 5 },
  comment: { type: String, trim: true, maxlength: 500, default: '' },
  customerName: { type: String, trim: true, maxlength: 100, default: '' },
  token: { type: String, required: true, index: true },
}, { timestamps: true });

feedbackSchema.index({ order: 1 }, { unique: true });
module.exports = mongoose.model('Feedback', feedbackSchema);
