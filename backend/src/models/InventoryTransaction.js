const mongoose = require('mongoose');

const inventoryTransactionSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true, index: true },
    type: { type: String, enum: ['STOCK_IN', 'STOCK_OUT', 'ADJUSTMENT', 'SALE', 'VOID_RESTOCK'], required: true },
    quantity: { type: Number, required: true }, // positive for in, negative for out (stored signed)
    stockAfter: { type: Number, required: true },
    reason: { type: String, trim: true },
    order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order' },
    recordedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  },
  { timestamps: true }
);

inventoryTransactionSchema.index({ product: 1, createdAt: -1 });

module.exports = mongoose.model('InventoryTransaction', inventoryTransactionSchema);
