const { Product, InventoryTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/products?search=&category=&status=&page=&limit=
const listProducts = asyncHandler(async (req, res) => {
  const { search, category, status, lowStock } = req.query;
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);

  const filter = { isDeleted: false };
  if (category) filter.category = category;
  if (status) filter.status = status;
  if (search) filter.name = { $regex: search, $options: 'i' };

  let products = await Product.find(filter)
    .populate('category', 'name')
    .sort({ name: 1 })
    .skip((page - 1) * limit)
    .limit(limit);

  if (lowStock === 'true') {
    products = products.filter((p) => p.trackInventory && p.stock <= p.lowStockThreshold);
  }

  const total = await Product.countDocuments(filter);

  res.json({
    success: true,
    data: products,
    pagination: { page, limit, total, pages: Math.ceil(total / limit) },
  });
});

const getProduct = asyncHandler(async (req, res) => {
  const product = await Product.findOne({ _id: req.params.id, isDeleted: false }).populate('category', 'name');
  if (!product) throw new ApiError(404, 'Product not found.');
  res.json({ success: true, data: product });
});

const createProduct = asyncHandler(async (req, res) => {
  const { name, category, sellingPrice, costPrice, stock, lowStockThreshold, trackInventory, status, imageUrl } = req.body;

  if (!name || !name.trim()) throw new ApiError(400, 'Product name is required.');
  if (!category) throw new ApiError(400, 'Category is required.');
  if (sellingPrice === undefined || sellingPrice < 0) throw new ApiError(400, 'A valid selling price is required.');

  const product = await Product.create({
    name: name.trim(),
    category,
    sellingPrice,
    costPrice: costPrice || 0,
    stock: stock || 0,
    lowStockThreshold: lowStockThreshold ?? 10,
    trackInventory: trackInventory ?? true,
    status: status || 'available',
    imageUrl: imageUrl || '',
  });

  if (product.stock > 0) {
    await InventoryTransaction.create({
      product: product._id,
      type: 'STOCK_IN',
      quantity: product.stock,
      stockAfter: product.stock,
      reason: 'Initial stock on product creation',
      recordedBy: req.user._id,
    });
  }

  res.status(201).json({ success: true, data: product });
});

const updateProduct = asyncHandler(async (req, res) => {
  const product = await Product.findOne({ _id: req.params.id, isDeleted: false });
  if (!product) throw new ApiError(404, 'Product not found.');

  const editable = ['name', 'category', 'sellingPrice', 'costPrice', 'lowStockThreshold', 'trackInventory', 'status', 'imageUrl'];
  editable.forEach((field) => {
    if (req.body[field] !== undefined) product[field] = req.body[field];
  });

  await product.save();
  res.json({ success: true, data: product });
});

// Soft delete / deactivate
const deleteProduct = asyncHandler(async (req, res) => {
  const product = await Product.findById(req.params.id);
  if (!product) throw new ApiError(404, 'Product not found.');
  product.isDeleted = true;
  product.status = 'unavailable';
  await product.save();
  res.json({ success: true, message: 'Product deleted.' });
});

module.exports = { listProducts, getProduct, createProduct, updateProduct, deleteProduct };
