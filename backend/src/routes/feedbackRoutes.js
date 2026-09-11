const express = require('express');
const { protect, authorize } = require('../middleware/auth');
const { publicFeedbackLimiter } = require('../middleware/rateLimiters');
const { createFeedback, listFeedback } = require('../controllers/feedbackController');
const router = express.Router();
router.post('/', publicFeedbackLimiter, createFeedback);
router.get('/', protect, authorize('admin', 'manager'), listFeedback);
module.exports = router;
