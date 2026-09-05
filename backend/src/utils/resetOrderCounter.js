// One-off maintenance script: safely reset the `orderNumber` sequence so the
// NEXT new order becomes #1, WITHOUT deleting any historical orders.
//
// WHY THIS ISN'T A ONE-LINE "SET COUNTER TO 0":
// `Order.orderNumber` has a `unique: true` index (see models/Order.js). If
// orders #1-#55 already exist in the database and we just reset the counter
// to 0, the very next order would try to become #1 again and the insert
// would fail with a duplicate-key error (or, worse, if the unique index were
// ever missing, it would silently create a second real order numbered #1 —
// a serious billing/reporting bug). So this script:
//
//   1. Connects to the database and reports the current counter value, the
//      highest existing Order.orderNumber, and how many orders exist.
//   2. If there are ZERO existing orders, it is always safe to reset the
//      counter to 0 (next order -> #1). It does this automatically.
//   3. If orders already exist, it REFUSES to touch anything by default,
//      and explains why, unless you explicitly pass --archive-existing.
//
// --archive-existing mode (only for orders you truly don't want counted as
// "real" production history, e.g. test orders from development):
//   - Does NOT delete any order document.
//   - Tags every existing order with `preLaunchTestData: true` so it can
//     still be found/audited later (e.g. `Order.find({ preLaunchTestData: true })`).
//   - Shifts each existing order's `orderNumber` by +1,000,000 (e.g. #56 ->
//     #1000056) so the low numbers (1, 2, 3, ...) become free again while
//     every number stays unique (no collisions, unique index stays valid).
//   - Resets the counter to 0, so the next new order becomes #1.
//
// Run (dry run / report only):
//   node backend/src/utils/resetOrderCounter.js
//
// Run (actually archive existing orders and free up numbering from 1):
//   node backend/src/utils/resetOrderCounter.js --archive-existing
//
// NOTE: This script was NOT run against your production database from this
// environment — there is no network path from this sandbox to your MongoDB
// Atlas cluster. You (or your deploy pipeline) need to run it against the
// real database.

require('dotenv').config();

const dns = require('dns');
const mongoose = require('mongoose');

dns.setServers(['8.8.8.8', '8.8.4.4']);

const { Order, Counter } = require('../models');

const ARCHIVE_OFFSET = 1000000;

async function main() {
  const archive = process.argv.includes('--archive-existing');

  const mongoUri = process.env.MONGODB_URI;
  if (!mongoUri) {
    throw new Error('MONGODB_URI is not configured.');
  }

  console.log('Connecting to MongoDB...');
  await mongoose.connect(mongoUri);
  console.log('Connected.\n');

  const totalOrders = await Order.countDocuments({});
  const highest = await Order.findOne({}).sort({ orderNumber: -1 }).select('orderNumber').lean();
  const counterDoc = await Counter.findById('orderNumber').lean();

  console.log('Current state:');
  console.log(`  Existing orders        : ${totalOrders}`);
  console.log(`  Highest orderNumber    : ${highest ? highest.orderNumber : '(none)'}`);
  console.log(`  Counter("orderNumber") : ${counterDoc ? counterDoc.seq : '(not created yet)'}`);
  console.log('');

  if (totalOrders === 0) {
    await Counter.findByIdAndUpdate('orderNumber', { $set: { seq: 0 } }, { upsert: true });
    console.log('No existing orders found — safe to reset.');
    console.log('Counter("orderNumber") reset to 0. The next order will be #1.');
    await mongoose.disconnect();
    process.exit(0);
    return;
  }

  if (!archive) {
    console.log(`${totalOrders} order(s) already exist, including orderNumber #${highest.orderNumber}.`);
    console.log('Refusing to reset the counter: the next order would try to reuse an');
    console.log('orderNumber that is already taken, which the unique index on');
    console.log('Order.orderNumber would reject (or, if that index were ever missing,');
    console.log('would create a duplicate real order number).');
    console.log('');
    console.log('Nothing was changed. If these are pre-launch/test orders you want out');
    console.log('of the way (kept, not deleted, but renumbered above 1,000,000 and');
    console.log('tagged preLaunchTestData: true) so real orders can start at #1, re-run:');
    console.log('');
    console.log('  node backend/src/utils/resetOrderCounter.js --archive-existing');
    await mongoose.disconnect();
    process.exit(0);
    return;
  }

  console.log(`Archiving ${totalOrders} existing order(s)...`);
  const allOrders = await Order.find({}).select('_id orderNumber').sort({ orderNumber: 1 }).lean();

  for (const o of allOrders) {
    if (o.orderNumber >= ARCHIVE_OFFSET) continue; // already archived, skip
    await Order.updateOne(
      { _id: o._id },
      { $set: { orderNumber: o.orderNumber + ARCHIVE_OFFSET, preLaunchTestData: true } }
    );
  }

  await Counter.findByIdAndUpdate('orderNumber', { $set: { seq: 0 } }, { upsert: true });

  console.log('Done.');
  console.log(`  ${allOrders.length} order(s) renumbered into the 1,000,000+ range and tagged preLaunchTestData: true.`);
  console.log('  Counter("orderNumber") reset to 0. The next new order will be #1.');
  console.log('  No order documents were deleted.');

  await mongoose.disconnect();
  process.exit(0);
}

main().catch(async (err) => {
  console.error('Reset failed:', err.message || err);
  try { await mongoose.disconnect(); } catch (_) {}
  process.exit(1);
});
