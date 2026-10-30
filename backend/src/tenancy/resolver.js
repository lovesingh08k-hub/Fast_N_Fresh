const { ApiError } = require('../utils/apiError');
const { Tenant } = require('../platform/models');
const { databaseFor } = require('./connections');

// Looks up clients (tenants) in the platform registry, enforces their
// licence, and builds the request context (see context.js).

const CACHE_MS = 30 * 1000;
const cache = new Map(); // key -> { tenant, at }

function cached(key) {
  const hit = cache.get(key);
  return hit && Date.now() - hit.at < CACHE_MS ? hit.tenant : undefined;
}

function remember(tenant) {
  const entry = { tenant, at: Date.now() };
  cache.set(`id:${tenant._id}`, entry);
  cache.set(`code:${tenant.code}`, entry);
  if (tenant.isDefault) cache.set('default', entry);
}

/** Drops cached clients, e.g. after the vendor changes a licence. */
function forgetTenants() {
  cache.clear();
}

async function findTenant(key, query) {
  const hit = cached(key);
  if (hit !== undefined) return hit;
  const tenant = await Tenant().findOne(query).select('+dbUri');
  if (tenant) remember(tenant);
  else cache.set(key, { tenant: null, at: Date.now() });
  return tenant;
}

const tenantById = (id) => findTenant(`id:${id}`, { _id: id });
const tenantByCode = (code) =>
  findTenant(`code:${String(code).trim().toLowerCase()}`, { code: String(code).trim().toLowerCase() });
/** The client used when no business code is given (older app versions). */
const defaultTenant = () => findTenant('default', { isDefault: true });

/** Refuses the request when the client's licence is not active. */
function assertLicence(tenant) {
  const problem = tenant.licenceProblem();
  if (problem) throw new ApiError(402, problem, { code: 'LICENCE_INACTIVE' });
}

function activeOutlets(tenant) {
  return tenant.outlets.filter((o) => o.active);
}

/** Outlets this user may open: admins all, others their assigned ones (none assigned = all). */
function outletsForUser(tenant, user) {
  const active = activeOutlets(tenant);
  const assigned = (user?.outlets || []).map(String);
  if (!user || user.role === 'admin' || assigned.length === 0) return active;
  return active.filter((o) => assigned.includes(o.code));
}

function findOutlet(outlets, requested) {
  if (!requested) return undefined;
  const key = String(requested).trim().toLowerCase();
  return outlets.find((o) => o.code === key || String(o._id) === key);
}

/**
 * The outlet a request works on: the requested one if the user may use it,
 * otherwise the user's first outlet.
 */
function pickOutlet(tenant, user, requested) {
  const allowed = outletsForUser(tenant, user);
  if (allowed.length === 0) {
    throw new ApiError(402, 'No active outlet is available for this account. Please contact your POS provider.', {
      code: 'LICENCE_INACTIVE',
    });
  }
  if (requested) {
    const outlet = findOutlet(allowed, requested);
    if (!outlet) throw new ApiError(403, 'You do not have access to this outlet.');
    return outlet;
  }
  return allowed[0];
}

function coreDbFor(tenant) {
  return databaseFor(tenant.dbUri, tenant.coreDb);
}

function buildContext(tenant, outlet) {
  return {
    tenant,
    outlet,
    coreDb: coreDbFor(tenant),
    outletDb: databaseFor(tenant.dbUri, outlet.dbName),
  };
}

/**
 * Public (customer QR menu) requests name their outlet as
 * "<businessCode>:<outletCode>" (query `o`); without it they go to the
 * default client's first outlet, so already-printed QR codes keep working.
 */
async function publicContext(outletKey) {
  let tenant;
  let outletCode;
  if (outletKey) {
    const [code, outlet] = String(outletKey).split(':');
    tenant = await tenantByCode(code);
    outletCode = outlet;
    if (!tenant) throw new ApiError(404, 'This menu link is not valid.');
  } else {
    tenant = await defaultTenant();
    if (!tenant) return null; // single-cafe setup without a platform registry
  }
  assertLicence(tenant);
  const outlets = activeOutlets(tenant);
  const outlet = outletCode ? findOutlet(outlets, outletCode) : outlets[0];
  if (!outlet) throw new ApiError(404, 'This outlet is not available.');
  return buildContext(tenant, outlet);
}

/** "<businessCode>:<outletCode>" for links that must reach one outlet. */
function outletKey(ctx) {
  return ctx ? `${ctx.tenant.code}:${ctx.outlet.code}` : '';
}

module.exports = {
  tenantById,
  tenantByCode,
  defaultTenant,
  forgetTenants,
  assertLicence,
  outletsForUser,
  pickOutlet,
  coreDbFor,
  buildContext,
  publicContext,
  outletKey,
};
