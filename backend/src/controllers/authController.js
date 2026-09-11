const { User } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { signToken } = require('../utils/jwt');

// POST /api/auth/login
// Accepts either username or phone in `identifier`.
const login = asyncHandler(async (req, res) => {
  const { identifier, password } = req.body;

  if (!identifier || !password) {
    throw new ApiError(400, 'Username/phone and password are required.');
  }

  const query = {
    $or: [
      { username: identifier.toLowerCase().trim() },
      { phone: identifier.trim() },
    ],
  };

  const user = await User.findOne(query).select('+passwordHash');

  if (!user) {
    throw new ApiError(401, 'Invalid credentials.');
  }

  if (user.status !== 'active') {
    throw new ApiError(
      403,
      'Your account has been deactivated. Contact the admin.',
    );
  }

  const isMatch = await user.comparePassword(password);

  if (!isMatch) {
    throw new ApiError(401, 'Invalid credentials.');
  }

  user.lastLoginAt = new Date();
  await user.save();

  const token = signToken(user);

  res.json({
    success: true,
    message: 'Login successful',
    data: {
      token,
      user: user.toSafeJSON(),
    },
  });
});

// GET /api/auth/me
const getMe = asyncHandler(async (req, res) => {
  res.json({
    success: true,
    data: req.user.toSafeJSON(),
  });
});

// POST /api/auth/change-password
const changePassword = asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;

  if (!currentPassword || !newPassword) {
    throw new ApiError(
      400,
      'Current and new password are required.',
    );
  }

  if (newPassword.length < 6) {
    throw new ApiError(
      400,
      'New password must be at least 6 characters.',
    );
  }

  const user = await User.findById(req.user._id).select('+passwordHash');

  if (!user) {
    throw new ApiError(401, 'Account no longer exists.');
  }

  const isMatch = await user.comparePassword(currentPassword);

  // Wrong current password is a validation error, not an
  // expired/invalid authentication session.
  if (!isMatch) {
    throw new ApiError(
      400,
      'Current password is incorrect.',
    );
  }

  await user.setPassword(newPassword);
  await user.save();

  res.json({
    success: true,
    message: 'Password changed successfully.',
  });
});

// POST /api/auth/logout-all
// Invalidates all previously issued tokens for this user.
const logoutAllDevices = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);

  if (!user) {
    throw new ApiError(401, 'Account no longer exists.');
  }

  user.tokenVersion = (user.tokenVersion || 0) + 1;

  await user.save();

  res.json({
    success: true,
    message: 'Logged out from all devices.',
  });
});

// POST /api/auth/push-token
// Registers (or refreshes) this device's Firebase Cloud Messaging token so
// new-order pushes can reach it even when the app is fully closed, not
// just backgrounded. A user can be signed in on more than one device, so
// tokens are stored as a de-duplicated array rather than a single field.
const registerPushToken = asyncHandler(async (req, res) => {
  const token = (req.body && req.body.token || '').trim();

  if (!token) {
    throw new ApiError(400, 'A push token is required.');
  }

  await User.updateOne(
    { _id: req.user._id },
    { $addToSet: { fcmTokens: token } },
  );

  res.json({ success: true, message: 'Push token registered.' });
});

// POST /api/auth/push-token/unregister
// Called on logout so a signed-out device stops receiving pushes meant
// for whoever is signed in next on that phone.
const unregisterPushToken = asyncHandler(async (req, res) => {
  const token = (req.body && req.body.token || '').trim();

  if (!token) {
    throw new ApiError(400, 'A push token is required.');
  }

  await User.updateOne(
    { _id: req.user._id },
    { $pull: { fcmTokens: token } },
  );

  res.json({ success: true, message: 'Push token unregistered.' });
});

module.exports = {
  login,
  getMe,
  changePassword,
  logoutAllDevices,
  registerPushToken,
  unregisterPushToken,
};