const express = require('express');
const { protect, authorize } = require('../middleware/auth');
const { uploadProductImage: uploadMiddleware } = require('../middleware/upload');
const { uploadProductImage } = require('../controllers/uploadController');

const router = express.Router();

router.use(protect);

// Product photos follow the same permission as product management itself
// (existing policy: admin only — see productRoutes.js).
router.post('/product-image', authorize('admin'), uploadMiddleware.single('image'), uploadProductImage);

module.exports = router;
