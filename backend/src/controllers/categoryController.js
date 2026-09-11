const { Category, Product } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

const listCategories = asyncHandler(async (req, res) => {
  const filter = {};
  if (req.query.status) filter.status = req.query.status;
  const categories = await Category.find(filter).sort({ sortOrder: 1, name: 1 });
  res.json({ success: true, data: categories });
});

const createCategory = asyncHandler(async (req, res) => {
  const { name, sortOrder } = req.body;
  if (!name || !name.trim()) throw new ApiError(400, 'Category name is required.');
  const category = await Category.create({ name: name.trim(), sortOrder: sortOrder || 0 });
  res.status(201).json({ success: true, data: category });
});

const updateCategory = asyncHandler(async (req, res) => {
  const { name, sortOrder, status } = req.body;
  const category = await Category.findById(req.params.id);
  if (!category) throw new ApiError(404, 'Category not found.');

  if (name !== undefined) category.name = name.trim();
  if (sortOrder !== undefined) category.sortOrder = sortOrder;
  if (status !== undefined) category.status = status;
  await category.save();

  res.json({ success: true, data: category });
});

const deleteCategory = asyncHandler(async (req, res) => {
  const inUse = await Product.exists({ category: req.params.id, isDeleted: false });
  if (inUse) {
    throw new ApiError(409, 'Cannot delete a category that still has products. Deactivate it instead.');
  }
  const category = await Category.findByIdAndDelete(req.params.id);
  if (!category) throw new ApiError(404, 'Category not found.');
  res.json({ success: true, message: 'Category deleted.' });
});

module.exports = { listCategories, createCategory, updateCategory, deleteCategory };
