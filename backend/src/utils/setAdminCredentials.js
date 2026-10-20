// One-off, production-safe admin login reset.
// Usage: npm run set:admin -- <username> <password> [<current admin username>]
// The third argument picks which admin to change when there is more than one.
//
// Changes ONLY the admin account's username and password. Unlike
// `npm run seed`, it never deletes other admins or adds sample menu data.
// All existing sessions for that admin are signed out.
require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const { User } = require('../models');

async function main() {
  const [rawUsername, password, rawFrom] = process.argv.slice(2);
  const fromUsername = String(rawFrom || '').trim().toLowerCase();
  const username = String(rawUsername || '').trim().toLowerCase();

  if (!username || !password) {
    throw new Error('Usage: npm run set:admin -- <username> <password>');
  }
  if (password.length < 6) {
    throw new Error('Password must be at least 6 characters.');
  }

  await connectDB();

  // Prefer an admin that already has this username; otherwise there must be
  // exactly one admin, so we never guess which account to take over.
  let admin = fromUsername
    ? await User.findOne({ username: fromUsername, role: 'admin' })
    : await User.findOne({ username, role: 'admin' });
  if (fromUsername && !admin) {
    throw new Error(`No admin account named "${fromUsername}". Nothing changed.`);
  }
  if (!admin) {
    const admins = await User.find({ role: 'admin' }).select('username');
    if (admins.length !== 1) {
      throw new Error(
        `Expected exactly one admin account, found ${admins.length}: ${admins.map((a) => a.username).join(', ') || 'none'}. Nothing changed.`
      );
    }
    admin = await User.findById(admins[0]._id);
  }

  const clash = await User.findOne({ username, _id: { $ne: admin._id } }).select('username role');
  if (clash) {
    throw new Error(`Username "${username}" is already used by a ${clash.role} account. Nothing changed.`);
  }

  const previousUsername = admin.username;
  admin.username = username;
  admin.status = 'active';
  await admin.setPassword(password);
  admin.tokenVersion = (admin.tokenVersion || 0) + 1;
  await admin.save();

  console.log(`Admin login updated: "${previousUsername}" -> "${username}". Password changed; old sessions signed out.`);
}

main()
  .catch((err) => {
    console.error('Failed:', err.message);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
