const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { ApiError } = require('../utils/apiError');

const uploadDir = path.join(__dirname, '..', '..', 'uploads', 'products');
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const safeExt = ['.jpg', '.jpeg', '.png', '.webp'].includes(ext) ? ext : '.jpg';
    cb(null, `product_${Date.now()}_${Math.round(Math.random() * 1e6)}${safeExt}`);
  },
});

const fileFilter = (req, file, cb) => {
  const allowed = ['image/jpeg', 'image/png', 'image/webp'];
  if (!allowed.includes(file.mimetype)) {
    return cb(new ApiError(400, 'Only JPG, PNG, or WEBP images are allowed.'));
  }
  cb(null, true);
};

// 5MB limit keeps this performant — the mobile client also compresses/resizes
// before upload (see ImageService in the Flutter app), this is a hard backstop.
const uploadProductImage = multer({ storage, fileFilter, limits: { fileSize: 5 * 1024 * 1024 } });

module.exports = { uploadProductImage };
