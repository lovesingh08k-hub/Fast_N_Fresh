const fs = require('fs/promises');
const { ImageAsset } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { currentContext } = require('../tenancy/context');
const { outletKey } = require('../tenancy/resolver');

// POST /api/uploads/product-image
// Stores the small compressed product thumbnail in MongoDB so product photos
// survive Render restarts/redeploys. The mobile picker intentionally compresses
// images to tiny thumbnails before upload.
const uploadProductImage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new ApiError(400, 'No image file was uploaded.');
  }

  let asset;
  try {
    const data = await fs.readFile(req.file.path);
    if (data.length > 1024 * 1024) {
      throw new ApiError(400, 'Image is too large after compression.');
    }

    asset = await ImageAsset.create({
      data,
      contentType: req.file.mimetype,
    });
  } finally {
    // The temp file is never needed once read, whether or not saving worked.
    await fs.unlink(req.file.path).catch(() => {});
  }

  const key = outletKey(currentContext());
  res.status(201).json({
    success: true,
    // Photos live in the outlet's database; the link names the outlet.
    data: { url: `/uploads/products/${asset._id}${key ? `?o=${encodeURIComponent(key)}` : ''}` },
  });
});

module.exports = { uploadProductImage };
