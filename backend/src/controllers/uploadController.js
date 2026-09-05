const { ApiError, asyncHandler } = require('../utils/apiError');

// POST /api/uploads/product-image  (multipart/form-data, field name "image")
// Returns a relative URL the client stores on Product.imageUrl. The actual
// file is served statically from /uploads (see app.js) — no hard-coded
// absolute paths, so this works the same in dev and production regardless
// of API_BASE_URL.
const uploadProductImage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new ApiError(400, 'No image file was uploaded.');
  }
  const relativeUrl = `/uploads/products/${req.file.filename}`;
  res.status(201).json({ success: true, data: { url: relativeUrl } });
});

module.exports = { uploadProductImage };
