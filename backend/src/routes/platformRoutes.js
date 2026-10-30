const express = require('express');
const c = require('../platform/controller');
const { loginLimiter } = require('../middleware/rateLimiters');

// Vendor-only API for the Platform Admin panel (/platform/). Separate login
// from the clients' staff; client tokens are not accepted here.
const router = express.Router();

router.post('/auth/login', loginLimiter, c.login);

router.use(c.protectPlatform);
router.get('/tenants', c.listTenants);
router.post('/tenants', c.createTenant);
router.patch('/tenants/:id', c.updateTenant);
router.post('/tenants/:id/outlets', c.addOutlet);
router.patch('/tenants/:id/outlets/:outletId', c.updateOutlet);
router.post('/tenants/:id/owner-password', c.resetOwnerPassword);
router.get('/tenants/:id/usage', c.tenantUsage);

module.exports = router;
