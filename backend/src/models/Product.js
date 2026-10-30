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
    // GST rate for this item (e.g. 5, 12, 18). Empty = the outlet's default rate.
    taxRate: { type: Number, default: null, min: 0, max: 40 },
    // Short line shown under the name on the menu ("Cheesy, served with dip").
    description: { type: String, trim: true, default: '', maxlength: 160 },
    // Indian food mark printed/shown next to the item: veg / non_veg / egg.
    foodType: { type: String, enum: ['', 'veg', 'non_veg', 'egg'], default: '' },
    status: { type: String, enum: ['available', 'unavailable'], default: 'available' },
    isDeleted: { type: Boolean, default: false },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text' });
productSchema.index({ isDeleted: 1, status: 1 });

module.exports = mongoose.model('Product', productSchema);
