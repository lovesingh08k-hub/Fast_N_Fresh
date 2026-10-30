// One-time platform setup (safe to run again).
// Usage: npm run platform:init -- <vendorUsername> <vendorPassword> [<businessCode>]
//
// 1. Creates (or resets the password of) the vendor's Platform Admin login,
//    used at https://<api-host>/platform/.
// 2. Registers the existing single-cafe database (MONGODB_URI) as the
//    default client with one outlet, so its data, users, printed QR codes
//    and already-installed apps keep working unchanged. Its staff log in
//    with this business code (older app versions need none).
require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const { Tenant, PlatformAdmin } = require('../platform/models');
const { BusinessSettings } = require('../models');

async function main() {
  const [rawUser, password, rawCode] = process.argv.slice(2);
  const username = String(rawUser || '').trim().toLowerCase();
  if (!username || !password || password.length < 6) {
    throw new Error('Usage: npm run platform:init -- <vendorUsername> <vendorPassword (6+ chars)> [<businessCode>]');
  }

  await connectDB();

  const Admin = PlatformAdmin();
  let admin = await Admin.findOne({ username });
  if (!admin) admin = new Admin({ username, name: username });
  await admin.setPassword(password);
  admin.tokenVersion = (admin.tokenVersion || 0) + 1;
  await admin.save();
  console.log(`Platform Admin login ready: ${username}`);

  const T = Tenant();
  const existing = await T.findOne({ isDefault: true });
  if (existing) {
    console.log(`Default client already registered: ${existing.code} (${existing.name})`);
    return;
  }

  const dbName = mongoose.connection.name;
  const settings = await BusinessSettings.getSettings();
  const code = String(rawCode || dbName.split('_')[0] || 'main')
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '')
    .slice(0, 16);

  const tenant = await T.create({
    code,
    name: settings.cafeName || code,
    isDefault: true,
    maxOutlets: 1,
    coreDb: dbName, // users stay where they are
    outlets: [{ code: 'main', name: settings.cafeName || code, dbName, phone: settings.phone || '', address: settings.address || '' }],
    contact: { phone: settings.phone || '' },
  });
  console.log(`Registered the existing database "${dbName}" as client "${tenant.code}" (outlet "main").`);
  console.log(`Staff log in with business code: ${tenant.code}`);
}

main()
  .catch((err) => {
    console.error('Platform init failed:', err.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    try { await mongoose.connection.close(); } catch (_) {}
  });
