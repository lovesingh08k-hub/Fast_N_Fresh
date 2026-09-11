const dns = require('dns');
dns.setServers(['8.8.8.8', '8.8.4.4']);

require('dotenv').config();
const mongoose = require('mongoose');
const { Order, Counter } = require('../models');

/**
 * Development/staging reset: removes all order history and starts the
 * human-readable order number from #1. This is intentionally guarded so it
 * cannot be run accidentally.
 */
async function resetFreshDatabase() {
  if (String(process.env.CONFIRM_FRESH_RESET || '') !== 'YES') {
    throw new Error('Set CONFIRM_FRESH_RESET=YES to permanently delete order history.');
  }
  if (!process.env.MONGODB_URI) throw new Error('MONGODB_URI is not configured.');

  await mongoose.connect(process.env.MONGODB_URI);
  try {
    const result = await Order.deleteMany({});
    await Counter.findByIdAndUpdate('orderNumber', { $set: { seq: 0 } }, { upsert: true });
    console.log(`Deleted ${result.deletedCount || 0} orders.`);
    console.log('Order counter reset. The next order will be #1.');
  } finally {
    await mongoose.disconnect();
  }
}

resetFreshDatabase().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

