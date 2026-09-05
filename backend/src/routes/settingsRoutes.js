const express = require('express');
const { getSettings, updateSettings } = require('../controllers/settingsController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.get('/', getSettings); // any authenticated user can read (needed for receipts/branding)
router.put('/', authorize('admin'), updateSettings); // only admin can change business settings

module.exports = router;
