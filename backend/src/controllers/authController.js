const { User, modelOn } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { signToken } = require('../utils/jwt');
const {
  tenantByCode,
  defaultTenant,
  assertLicence,
  outletsForUser,
  coreDbFor,
  outletKey,
} = require('../tenancy/resolver');

/** Client (business) and outlet details the app needs after login. */
function sessionInfo(tenant, user, currentOutlet) {
  if (!tenant) return { business: null, outlets: [], currentOutlet: null };
  const outlets = outletsForUser(tenant, user).map((o) => ({
    id: String(o._id),
    code: o.code,
    name: o.name,
    key: `${tenant.code}:${o.code}`,
  }));
  return {
    business: {
      code: tenant.code,
      name: tenant.name,
      validUntil: tenant.validUntil,
      maxOutlets: tenant.maxOutlets,
    },
    outlets,
    currentOutlet: currentOutlet ? outlets.find((o) => o.code === currentOutlet.code) || null : outlets[0] || null,
  };
}

// POST /api/auth/login
// Accepts either username or phone in `identifier`, plus the business code
// of the client (cafe/restaurant). Without a business code (older app
// versions) the default client is used.
const login = asyncHandler(async (req, res) => {
  const { identifier, password } = req.body;
  const businessCode = typeof req.body.businessCode === 'string' ? req.body.businessCode.trim() : '';

  if (!identifier || !password || typeof identifier !== 'string' || typeof password !== 'string') {
    throw new ApiError(400, 'Username/phone and password are required.');
  }

  const tenant = businessCode ? await tenantByCode(businessCode) : await defaultTenant();
  if (businessCode && !tenant) {
    throw new ApiError(401, 'Invalid business code, username or password.');
  }
  const UserModel = tenant ? modelOn(coreDbFor(tenant), 'User') : User;

  const query = {
    $or: [
      { username: identifier.toLowerCase().trim() },
      { phone: identifier.trim() },
    ],
  };

  const user = await UserModel.findOne(query).select('+passwordHash');

  if (!user) {
    throw new ApiError(401, 'Invalid credentials.');
  }

  const isMatch = await user.comparePassword(password);

  if (!isMatch) {
    throw new ApiError(401, 'Invalid credentials.');
  }

  // Checked only after the password, so the response can't be used to
  // discover which usernames exist.
  if (user.status !== 'active') {
    throw new ApiError(
      403,
      'Your account has been deactivated. Contact the admin.',
    );
  }
  if (tenant) assertLicence(tenant);

  const session = sessionInfo(tenant, user);
  if (tenant && !session.currentOutlet) {
    throw new ApiError(402, 'No active outlet is available for this account. Please contact your POS provider.', {
      code: 'LICENCE_INACTIVE',
    });
  }

  user.lastLoginAt = new Date();
  await user.save();

  const token = signToken(user, tenant);

  res.json({
    success: true,
    message: 'Login successful',
    data: {
      token,
      user: user.toSafeJSON(),
      ...session,
    },
  });
});

// GET /api/auth/me
// The user, plus (for platform clients) the business, the outlets this user
// may open, and the outlet this request ran in.
const getMe = asyncHandler(async (req, res) => {
  const ctx = req.tenantContext;
  res.json({
    success: true,
    data: {
      ...req.user.toSafeJSON(),
      ...(ctx ? { session: { ...sessionInfo(ctx.tenant, req.user, ctx.outlet), outletKey: outletKey(ctx) } } : {}),
    },
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

  if (typeof currentPassword !== 'string' || typeof newPassword !== 'string') {
    throw new ApiError(400, 'Current and new password are required.');
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
  const token = String((req.body && req.body.token) || '').trim();

  if (!token) {
    throw new ApiError(400, 'A push token is required.');
  }

  // A device token belongs to whoever is signed in on that phone now. Drop it
  // from any previous user so they stop receiving this device's pushes.
  await User.updateMany(
    { _id: { $ne: req.user._id }, fcmTokens: token },
    { $pull: { fcmTokens: token } },
  );

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
  const token = String((req.body && req.body.token) || '').trim();

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