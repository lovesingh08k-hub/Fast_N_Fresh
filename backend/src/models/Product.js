const mongoose = require('mongoose');

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, index: true },
    category: { type: mongoose.Schema.Types.ObjectId, ref: 'Category', required: true },
    sellingPrice: { type: Number, required: true, min: 0 },
    costPrice: { type: Number, default: 0, min: 0 },
    imageUrl: { type: String, trim: true, default: '' }, // relative URL under /uploads, served statically
    trackInventory: { type: Boolean, default: true },
    stock: { type: Number, default: 0 },
    lowStockThreshold: { type: Number, default: 10 },
    recipe: [{
      ingredient: { type: mongoose.Schema.Types.ObjectId, ref: 'Product' },
      quantity: { type: Number, min: 0.001 },
      unit: { type: String, trim: true, default: 'unit' },
    }],
    status: { type: String, enum: ['available', 'unavailable'], default: 'available' },
    isDeleted: { type: Boolean, default: false },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text' });
productSchema.index({ isDeleted: 1, status: 1 });

module.exports = mongoose.model('Product', productSchema);
