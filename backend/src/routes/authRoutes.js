const express = require('express');
const { login, getMe, changePassword, logoutAllDevices, registerPushToken, unregisterPushToken } = require('../controllers/authController');
const { protect } = require('../middleware/auth');
const { loginLimiter } = require('../middleware/rateLimiters');

const router = express.Router();

router.post('/login', loginLimiter, login);
router.get('/me', protect, getMe);
router.post('/change-password', protect, changePassword);
router.post('/logout-all', protect, logoutAllDevices);
router.post('/push-token', protect, registerPushToken);
router.post('/push-token/unregister', protect, unregisterPushToken);

module.exports = router;
