const { verifyToken } = require('../utils/jwt');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { User } = require('../models');

// Verifies the JWT, loads the current user, and rejects if the user was
// deactivated or if tokenVersion was bumped (logout-all-devices).
const protect = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.split(' ')[1] : null;

  if (!token) {
    throw new ApiError(401, 'Not authenticated. Please log in.');
  }

  let payload;
  try {
    payload = verifyToken(token);
  } catch (err) {
    throw new ApiError(401, 'Session expired or invalid. Please log in again.');
  }

  const user = await User.findById(payload.sub);
  if (!user) {
    throw new ApiError(401, 'Account no longer exists.');
  }
  if (user.status !== 'active') {
    throw new ApiError(403, 'Your account has been deactivated. Contact the admin.');
  }
  if ((user.tokenVersion || 0) !== payload.tokenVersion) {
    throw new ApiError(401, 'Session expired. Please log in again.');
  }

  req.user = user; // full mongoose doc (no passwordHash selected by default)
  next();
});

// Role-based authorization. Usage: authorize('admin') or authorize('admin', 'staff')
const authorize = (...roles) => (req, res, next) => {
  if (!req.user) {
    throw new ApiError(401, 'Not authenticated.');
  }
  if (!roles.includes(req.user.role)) {
    throw new ApiError(403, 'You do not have permission to perform this action.');
  }
  next();
};

module.exports = { protect, authorize };
