const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const { platformDb } = require('../tenancy/connections');

// Platform registry: the vendor's list of clients (cafes/restaurants/
// franchises), their licences and outlets. Lives in its own database
// (PLATFORM_DB_NAME, default "pwp_platform") on the main cluster.

const outletSchema = new mongoose.Schema(
  {
    code: { type: String, required: true, trim: true, lowercase: true, match: /^[a-z0-9-]{2,12}$/ },
    name: { type: String, required: true, trim: true },
    dbName: { type: String, required: true, trim: true },
    active: { type: Boolean, default: true },
    address: { type: String, trim: true, default: '' },
    phone: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
);

const tenantSchema = new mongoose.Schema(
  {
    // Typed by the client's staff on the login screen.
    code: { type: String, required: true, unique: true, trim: true, lowercase: true, match: /^[a-z0-9-]{3,16}$/ },
    name: { type: String, required: true, trim: true },
    status: { type: String, enum: ['active', 'suspended'], default: 'active' },
    // Licence end date; null = no expiry. After it, logins and API calls are refused.
    validUntil: { type: Date, default: null },
    // How many outlets this client may run (franchise). 1 = single cafe.
    maxOutlets: { type: Number, default: 1, min: 1 },
    plan: { type: String, trim: true, default: 'standard' },
    // Optional separate MongoDB cluster for this client (e.g. its own free
    // Atlas cluster, so its storage is not shared). Empty = main cluster.
    dbUri: { type: String, trim: true, default: '', select: false },
    coreDb: { type: String, required: true, trim: true }, // users
    outlets: { type: [outletSchema], default: [] },
    // Logins without a business code (older app versions) use this client.
    isDefault: { type: Boolean, default: false },
    contact: {
      name: { type: String, trim: true, default: '' },
      phone: { type: String, trim: true, default: '' },
      email: { type: String, trim: true, default: '' },
    },
    notes: { type: String, trim: true, default: '' },
    // Shown to the client's staff when the licence is not active.
    suspendedMessage: { type: String, trim: true, default: '' },
  },
  { timestamps: true }
);

tenantSchema.methods.licenceProblem = function licenceProblem(now = new Date()) {
  if (this.status !== 'active') {
    return this.suspendedMessage || 'This account is suspended. Please contact your POS provider.';
  }
  if (this.validUntil && this.validUntil < now) {
    return 'Your subscription has expired. Please contact your POS provider to renew.';
  }
  return null;
};

const platformAdminSchema = new mongoose.Schema(
  {
    username: { type: String, required: true, unique: true, trim: true, lowercase: true },
    name: { type: String, trim: true, default: '' },
    passwordHash: { type: String, required: true, select: false },
    tokenVersion: { type: Number, default: 0 },
  },
  { timestamps: true }
);

platformAdminSchema.methods.setPassword = async function setPassword(plain) {
  this.passwordHash = await bcrypt.hash(plain, 10);
};

platformAdminSchema.methods.comparePassword = function comparePassword(plain) {
  return bcrypt.compare(plain, this.passwordHash);
};

function Tenant() {
  const db = platformDb();
  return db.models.Tenant || db.model('Tenant', tenantSchema);
}

function PlatformAdmin() {
  const db = platformDb();
  return db.models.PlatformAdmin || db.model('PlatformAdmin', platformAdminSchema);
}

module.exports = { Tenant, PlatformAdmin };
