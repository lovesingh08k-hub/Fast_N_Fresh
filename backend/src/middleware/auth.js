const { verifyToken } = require('../utils/jwt');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { User, modelOn } = require('../models');
const { runWithContext } = require('../tenancy/context');
const {
  tenantById,
  defaultTenant,
  assertLicence,
  pickOutlet,
  coreDbFor,
  buildContext,
} = require('../tenancy/resolver');

// Verifies the JWT, loads the current user, and rejects if the user was
// deactivated or if tokenVersion was bumped (logout-all-devices).
//
// For a client of the platform it also checks the client's licence, picks
// the outlet (X-Outlet-Id header, else the user's first outlet) and runs
// the rest of the request inside that client/outlet's context, so every
// model reads and writes that outlet's database.
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
  // Platform (vendor) tokens are only valid on /api/platform.
  if (payload.scope) {
    throw new ApiError(401, 'Session expired or invalid. Please log in again.');
  }

  // Tokens from before multi-client support have no tenant id; they belong
  // to the default client (or the single-cafe setup when there is none).
  const tenant = payload.tid ? await tenantById(payload.tid) : await defaultTenant();
  if (payload.tid && !tenant) {
    throw new ApiError(401, 'Account no longer exists.');
  }
  if (tenant) assertLicence(tenant);

  const UserModel = tenant ? modelOn(coreDbFor(tenant), 'User') : User;
  const user = await UserModel.findById(payload.sub);
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

  if (!tenant) return next();

  const outlet = pickOutlet(tenant, user, req.get('x-outlet-id'));
  req.tenantContext = buildContext(tenant, outlet);
  return runWithContext(req.tenantContext, () => next());
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
