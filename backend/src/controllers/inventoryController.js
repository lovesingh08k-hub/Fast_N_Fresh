const mongoose = require('mongoose');
const { Product, InventoryTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/inventory — current stock levels for all tracked products
const getInventory = asyncHandler(async (req, res) => {
  const products = await Product.find({ isDeleted: false, trackInventory: true })
    .populate('category', 'name')
    .sort({ name: 1 });

  const lowStock = products.filter((p) => p.stock <= p.lowStockThreshold);

  res.json({
    success: true,
    data: {
      products,
      lowStockCount: lowStock.length,
      lowStockProducts: lowStock,
    },
  });
});

// GET /api/inventory/:productId/history
const getProductHistory = asyncHandler(async (req, res) => {
  const history = await InventoryTransaction.find({ product: req.params.productId })
    .populate('recordedBy', 'name')
    .sort({ createdAt: -1 })
    .limit(200);
  res.json({ success: true, data: history });
});

// POST /api/inventory/adjust  { productId, type: 'STOCK_IN'|'STOCK_OUT'|'ADJUSTMENT', quantity, reason }
const adjustInventory = asyncHandler(async (req, res) => {
  const { productId, type, quantity, reason } = req.body;

  if (!['STOCK_IN', 'STOCK_OUT', 'ADJUSTMENT'].includes(type)) {
    throw new ApiError(400, 'type must be STOCK_IN, STOCK_OUT, or ADJUSTMENT.');
  }
  const qty = Number(quantity);
  if (!Number.isFinite(qty) || qty === 0) {
    throw new ApiError(400, 'A non-zero quantity is required.');
  }

  let signedQty;
  if (type === 'STOCK_IN') signedQty = Math.abs(qty);
  else if (type === 'STOCK_OUT') signedQty = -Math.abs(qty);
  else signedQty = qty; // ADJUSTMENT can be positive or negative directly (set delta)

  const session = await mongoose.startSession();
  let updatedProduct;
  let transaction;

  try {
    await session.withTransaction(async () => {
      // Atomic increment: the $inc and the negative-stock guard happen in a
      // single DB operation, so two concurrent adjustments (or an
      // adjustment racing a sale's own stock deduction) can no longer
      // stomp on each other the way a findOne() -> compute -> save() chain
      // could. When decreasing stock, the filter only matches documents
      // whose current stock can absorb the decrease; if two decreases race,
      // whichever reaches Mongo second re-evaluates against the
      // already-updated value and is correctly rejected if it would go
      // negative, instead of silently overwriting the first one's result.
      const filter = { _id: productId, isDeleted: false };
      if (signedQty < 0) {
        filter.stock = { $gte: -signedQty };
      }

      updatedProduct = await Product.findOneAndUpdate(filter, { $inc: { stock: signedQty } }, { new: true, session });

      if (!updatedProduct) {
        // Filter didn't match — figure out why (missing vs. insufficient
        // stock) so the error message stays accurate under concurrency.
        const existing = await Product.findOne({ _id: productId, isDeleted: false }).session(session);
        if (!existing) throw new ApiError(404, 'Product not found.');
        throw new ApiError(400, `Adjustment would result in negative stock (current: ${existing.stock}).`);
      }

      [transaction] = await InventoryTransaction.create(
        [
          {
            product: updatedProduct._id,
            type,
            quantity: signedQty,
            stockAfter: updatedProduct.stock,
            reason,
            recordedBy: req.user._id,
          },
        ],
        { session }
      );
    });
  } finally {
    await session.endSession();
  }

  res.status(201).json({ success: true, data: { product: updatedProduct, transaction } });
});

module.exports = { getInventory, getProductHistory, adjustInventory };
