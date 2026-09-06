const fs = require('fs/promises');
const { ImageAsset } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// POST /api/uploads/product-image
// Stores the small compressed product thumbnail in MongoDB so product photos
// survive Render restarts/redeploys. The mobile picker intentionally compresses
// images to tiny thumbnails before upload.
const uploadProductImage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new ApiError(400, 'No image file was uploaded.');
  }

  const data = await fs.readFile(req.file.path);
  if (data.length > 1024 * 1024) {
    await fs.unlink(req.file.path).catch(() => {});
    throw new ApiError(400, 'Image is too large after compression.');
  }

  const asset = await ImageAsset.create({
    data,
    contentType: req.file.mimetype,
  });

  await fs.unlink(req.file.path).catch(() => {});

  res.status(201).json({
    success: true,
    data: { url: `/uploads/products/${asset._id}` },
  });
});

module.exports = { uploadProductImage };
