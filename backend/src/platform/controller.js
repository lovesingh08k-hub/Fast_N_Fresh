const jwt = require('jsonwebtoken');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { Tenant, PlatformAdmin } = require('./models');
const { modelOn, prepareDatabase } = require('../models');
const { databaseFor } = require('../tenancy/connections');
const { forgetTenants } = require('../tenancy/resolver');

// Vendor (platform owner) API: manage clients, their licences and outlets.
// Used by the Platform Admin panel at /platform/.

const PLATFORM_SCOPE = 'platform';

function signPlatformToken(admin) {
  return jwt.sign(
    { sub: admin._id.toString(), scope: PLATFORM_SCOPE, tokenVersion: admin.tokenVersion || 0 },
    process.env.JWT_SECRET,
    { expiresIn: '12h' }
  );
}

const protectPlatform = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new ApiError(401, 'Please log in.');
  let payload;
  try {
    payload = jwt.verify(token, process.env.JWT_SECRET);
  } catch (err) {
    throw new ApiError(401, 'Session expired. Please log in again.');
  }
  if (payload.scope !== PLATFORM_SCOPE) throw new ApiError(401, 'Please log in.');
  const admin = await PlatformAdmin().findById(payload.sub);
  if (!admin || (admin.tokenVersion || 0) !== payload.tokenVersion) {
    throw new ApiError(401, 'Session expired. Please log in again.');
  }
  req.platformAdmin = admin;
  next();
});

// POST /api/platform/auth/login
const login = asyncHandler(async (req, res) => {
  const username = String(req.body.username || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const admin = await PlatformAdmin().findOne({ username }).select('+passwordHash');
  if (!admin || !(await admin.comparePassword(password))) {
    throw new ApiError(401, 'Invalid username or password.');
  }
  res.json({ success: true, data: { token: signPlatformToken(admin), name: admin.name || admin.username } });
});

function outletDbName(tenantCode, outletCode) {
  return `pwp_${tenantCode}_${outletCode}`.replace(/-/g, '_');
}

function publicTenant(tenant) {
  const obj = tenant.toObject();
  obj.hasOwnDatabase = Boolean(tenant.dbUri);
  delete obj.dbUri;
  obj.licenceProblem = tenant.licenceProblem();
  return obj;
}

async function loadTenant(id) {
  const tenant = await Tenant().findById(id).select('+dbUri');
  if (!tenant) throw new ApiError(404, 'Client not found.');
  return tenant;
}

function parseDate(value) {
  if (value === null || value === '') return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new ApiError(400, 'Invalid date.');
  return date;
}

/** Sets up a new outlet database: business settings with its name, optionally a copy of another outlet's menu. */
async function initOutlet(tenant, outlet, copyFrom) {
  const db = databaseFor(tenant.dbUri, outlet.dbName);
  await prepareDatabase(db);
  const Settings = modelOn(db, 'BusinessSettings');
  const settings = await Settings.getSettings();
  settings.cafeName = outlet.name;
  if (outlet.phone) settings.phone = outlet.phone;
  if (outlet.address) settings.address = outlet.address;
  await settings.save();

  if (!copyFrom) return;
  const source = databaseFor(tenant.dbUri, copyFrom.dbName);
  const SrcCategory = modelOn(source, 'Category');
  const SrcProduct = modelOn(source, 'Product');
  const Category = modelOn(db, 'Category');
  const Product = modelOn(db, 'Product');
  const categoryMap = new Map();
  for (const cat of await SrcCategory.find({}).lean()) {
    const copy = await Category.create({ name: cat.name, sortOrder: cat.sortOrder, status: cat.status });
    categoryMap.set(String(cat._id), copy._id);
  }
  const products = await SrcProduct.find({ isDeleted: { $ne: true } }).lean();
  await Product.insertMany(
    products
      .filter((p) => categoryMap.has(String(p.category)))
      .map((p) => ({
        name: p.name,
        category: categoryMap.get(String(p.category)),
        sellingPrice: p.sellingPrice,
        costPrice: p.costPrice,
        trackInventory: p.trackInventory,
        stock: 0,
        lowStockThreshold: p.lowStockThreshold,
        status: p.status,
        // Photos live in the source outlet's database; not copied.
        imageUrl: '',
      }))
  );
}

// GET /api/platform/tenants
const listTenants = asyncHandler(async (req, res) => {
  const tenants = await Tenant().find({}).select('+dbUri').sort({ createdAt: -1 });
  res.json({ success: true, data: tenants.map(publicTenant) });
});

// POST /api/platform/tenants
// Creates a client with its first outlet and its owner (admin) login.
const createTenant = asyncHandler(async (req, res) => {
  const b = req.body || {};
  const code = String(b.code || '').trim().toLowerCase();
  const outletCode = String(b.outletCode || 'main').trim().toLowerCase();
  const owner = b.owner || {};
  if (!b.name || !code) throw new ApiError(400, 'Client name and business code are required.');
  if (!owner.username || !owner.password || String(owner.password).length < 6) {
    throw new ApiError(400, 'Owner username and a password of at least 6 characters are required.');
  }
  if (await Tenant().exists({ code })) throw new ApiError(409, 'This business code is already taken.');

  const tenant = new (Tenant())({
    code,
    name: b.name,
    validUntil: b.validUntil ? parseDate(b.validUntil) : null,
    maxOutlets: Math.max(1, Number(b.maxOutlets) || 1),
    plan: b.plan || 'standard',
    dbUri: String(b.dbUri || '').trim(),
    coreDb: `pwp_${code}`.replace(/-/g, '_'),
    contact: b.contact || {},
    notes: b.notes || '',
    outlets: [
      {
        code: outletCode,
        name: b.outletName || b.name,
        dbName: outletDbName(code, outletCode),
        address: b.address || '',
        phone: (b.contact && b.contact.phone) || '',
      },
    ],
  });
  await tenant.validate();

  const coreDb = databaseFor(tenant.dbUri, tenant.coreDb);
  await prepareDatabase(coreDb, { core: true });
  const User = modelOn(coreDb, 'User');
  const admin = new User({
    name: owner.name || 'Owner',
    username: String(owner.username).trim().toLowerCase(),
    phone: owner.phone || (b.contact && b.contact.phone) || '0000000000',
    role: 'admin',
  });
  await admin.setPassword(String(owner.password));
  await admin.save();
  await tenant.save();
  await initOutlet(tenant, tenant.outlets[0]);

  forgetTenants();
  res.status(201).json({ success: true, data: publicTenant(tenant) });
});

// PATCH /api/platform/tenants/:id
// Licence and details: status (active/suspended), validUntil, maxOutlets, ...
const updateTenant = asyncHandler(async (req, res) => {
  const tenant = await loadTenant(req.params.id);
  const b = req.body || {};
  for (const field of ['name', 'plan', 'notes', 'suspendedMessage']) {
    if (b[field] !== undefined) tenant[field] = b[field];
  }
  if (b.status !== undefined) tenant.status = b.status;
  if (b.validUntil !== undefined) tenant.validUntil = parseDate(b.validUntil);
  if (b.maxOutlets !== undefined) {
    const max = Number(b.maxOutlets);
    if (!Number.isInteger(max) || max < 1) throw new ApiError(400, 'Outlet limit must be 1 or more.');
    tenant.maxOutlets = max;
  }
  if (b.contact !== undefined) tenant.contact = { ...tenant.contact, ...b.contact };
  if (b.dbUri !== undefined) tenant.dbUri = String(b.dbUri || '').trim();
  await tenant.save();
  forgetTenants();
  res.json({ success: true, data: publicTenant(tenant) });
});

// POST /api/platform/tenants/:id/outlets
const addOutlet = asyncHandler(async (req, res) => {
  const tenant = await loadTenant(req.params.id);
  const b = req.body || {};
  const code = String(b.code || '').trim().toLowerCase();
  if (!b.name || !code) throw new ApiError(400, 'Outlet name and code are required.');
  if (tenant.outlets.length >= tenant.maxOutlets) {
    throw new ApiError(400, `This client may have ${tenant.maxOutlets} outlet(s). Raise the outlet limit first.`);
  }
  if (tenant.outlets.some((o) => o.code === code)) throw new ApiError(409, 'This outlet code already exists.');

  tenant.outlets.push({
    code,
    name: b.name,
    dbName: outletDbName(tenant.code, code),
    address: b.address || '',
    phone: b.phone || '',
  });
  await tenant.save();
  const outlet = tenant.outlets[tenant.outlets.length - 1];
  const copyFrom = b.copyMenuFrom ? tenant.outlets.find((o) => o.code === b.copyMenuFrom) : null;
  await initOutlet(tenant, outlet, copyFrom);
  forgetTenants();
  res.status(201).json({ success: true, data: publicTenant(tenant) });
});

// PATCH /api/platform/tenants/:id/outlets/:outletId  (name, active, address, phone)
const updateOutlet = asyncHandler(async (req, res) => {
  const tenant = await loadTenant(req.params.id);
  const outlet = tenant.outlets.id(req.params.outletId);
  if (!outlet) throw new ApiError(404, 'Outlet not found.');
  for (const field of ['name', 'active', 'address', 'phone']) {
    if (req.body[field] !== undefined) outlet[field] = req.body[field];
  }
  await tenant.save();
  forgetTenants();
  res.json({ success: true, data: publicTenant(tenant) });
});

// POST /api/platform/tenants/:id/owner-password  { username, password }
// Resets a client admin's password (e.g. the owner forgot it).
const resetOwnerPassword = asyncHandler(async (req, res) => {
  const tenant = await loadTenant(req.params.id);
  const password = String(req.body.password || '');
  if (password.length < 6) throw new ApiError(400, 'Password must be at least 6 characters.');
  const User = modelOn(databaseFor(tenant.dbUri, tenant.coreDb), 'User');
  const username = String(req.body.username || '').trim().toLowerCase();
  const user = username ? await User.findOne({ username }) : await User.findOne({ role: 'admin' }).sort({ createdAt: 1 });
  if (!user) throw new ApiError(404, 'User not found.');
  await user.setPassword(password);
  user.tokenVersion = (user.tokenVersion || 0) + 1;
  user.status = 'active';
  await user.save();
  res.json({ success: true, data: { username: user.username } });
});

// GET /api/platform/tenants/:id/usage
// Database size per outlet, to see who is close to the storage limit.
const tenantUsage = asyncHandler(async (req, res) => {
  const tenant = await loadTenant(req.params.id);
  const stats = async (dbName) => {
    try {
      const db = databaseFor(tenant.dbUri, dbName);
      await db.asPromise();
      const s = await db.db.stats();
      return { dataMB: +(s.dataSize / 1048576).toFixed(2), storageMB: +(s.storageSize / 1048576).toFixed(2), objects: s.objects };
    } catch (err) {
      return { error: err.message };
    }
  };
  const outlets = [];
  for (const outlet of tenant.outlets) {
    outlets.push({ code: outlet.code, name: outlet.name, ...(await stats(outlet.dbName)) });
  }
  res.json({ success: true, data: { core: await stats(tenant.coreDb), outlets } });
});

module.exports = {
  protectPlatform,
  login,
  listTenants,
  createTenant,
  updateTenant,
  addOutlet,
  updateOutlet,
  resetOwnerPassword,
  tenantUsage,
};
