// One-time production-safe cleanup for legacy duplicate admin accounts.
// Keeps the configured canonical admin and deletes only other role=admin docs.
require('dotenv').config();
const connectDB = require('../config/db');
const { User } = require('../models');

(async () => {
  try {
    await connectDB();
    const username = (process.env.SEED_ADMIN_USERNAME || 'admin').toLowerCase().trim();
    let canonical = await User.findOne({ username, role: 'admin' });

    if (!canonical) {
      canonical = await User.findOne({ role: 'admin' }).sort({ createdAt: 1 });
    }

    if (!canonical) {
      console.log('No admin accounts found. Nothing to clean.');
      return;
    }

    const result = await User.deleteMany({
      role: 'admin',
      _id: { $ne: canonical._id },
    });

    console.log('========================================');
    console.log('ADMIN CLEANUP COMPLETE');
    console.log('========================================');
    console.log('Canonical admin:', canonical.username);
    console.log('Duplicate admins removed:', result.deletedCount);
  } catch (err) {
    console.error('ADMIN CLEANUP FAILED:', err.message);
    process.exitCode = 1;
  } finally {
    const mongoose = require('mongoose');
    await mongoose.disconnect().catch(() => {});
  }
})();
