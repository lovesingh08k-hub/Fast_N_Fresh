const { asyncHandler } = require('../utils/apiError');
const { runWithContext } = require('../tenancy/context');
const { publicContext } = require('../tenancy/resolver');

// Customer-facing requests (QR menu, product photos) carry no login, so the
// outlet comes from the link: query `o` = "<businessCode>:<outletCode>".
// Links without it reach the default client, so QR codes printed before
// multi-client support keep working.
const withPublicOutlet = asyncHandler(async (req, res, next) => {
  const ctx = await publicContext(req.query.o || req.get('x-outlet-key'));
  if (!ctx) return next();
  req.tenantContext = ctx;
  return runWithContext(ctx, () => next());
});

module.exports = { withPublicOutlet };
