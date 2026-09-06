// One-off maintenance utility for safely resetting the human-readable order
// sequence. Existing orders are retained and, when explicitly archived, moved
// above ARCHIVE_OFFSET so the next real order can be #1.
//
// This module can be run from the CLI OR called by the temporary authenticated
// maintenance endpoint. It never accepts a MongoDB URI from an HTTP request.

require('dotenv').config();

const dns = require('dns');
const mongoose = require('mongoose');

dns.setServers(['8.8.8.8', '8.8.4.4']);

const { Order, Counter } = require('../models');

const ARCHIVE_OFFSET = 1000000;

async function resetOrderCounter({ archiveExisting = false } = {}) {
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

  const state = {
    existingOrders: totalOrders,
    highestOrderNumber: highest ? highest.orderNumber : null,
    counter: counterDoc ? counterDoc.seq : null,
  };

  if (totalOrders === 0) {
    await Counter.findByIdAndUpdate(
      'orderNumber',
      { $set: { seq: 0 } },
      { upsert: true }
    );
    return {
      ...state,
      changed: true,
      archived: 0,
      nextOrderNumber: 1,
      message: 'No existing orders found. Counter reset to 0; the next order will be #1.',
    };
  }

  if (!archiveExisting) {
    return {
      ...state,
      changed: false,
      archived: 0,
      nextOrderNumber: (counterDoc ? counterDoc.seq : 0) + 1,
      message: 'Existing orders found. Nothing was changed. Pass archiveExisting=true to archive them and restart at #1.',
    };
  }

  const session = await mongoose.startSession();
  let archived = 0;

  try {
    await session.withTransaction(async () => {
      const orders = await Order.find({})
        .select('_id orderNumber')
        .sort({ orderNumber: 1, _id: 1 })
        .session(session)
        .lean();

      // First move every existing number to a temporary negative value. This
      // avoids collisions with the final 1,000,000+ values while the unique
      // orderNumber index remains enabled.
      for (let i = 0; i < orders.length; i += 1) {
        await Order.updateOne(
          { _id: orders[i]._id },
          {
            $set: {
              orderNumber: -(ARCHIVE_OFFSET + i + 1),
              preLaunchTestData: true,
            },
          },
          { session }
        );
      }

      // Then assign the permanent archived numbers.
      for (const order of orders) {
        await Order.updateOne(
          { _id: order._id },
          { $set: { orderNumber: order.orderNumber + ARCHIVE_OFFSET } },
          { session }
        );
      }

      await Counter.findByIdAndUpdate(
        'orderNumber',
        { $set: { seq: 0 } },
        { upsert: true, session }
      );

      archived = orders.length;
    });
  } finally {
    await session.endSession();
  }

  return {
    ...state,
    changed: true,
    archived,
    nextOrderNumber: 1,
    message: `Archived ${archived} existing order(s). Counter reset to 0; the next order will be #1.`,
  };
}

async function main() {
  const archiveExisting = process.argv.includes('--archive-existing');

  try {
    console.log('========================================');
    console.log('ORDER COUNTER RESET');
    console.log('========================================');

    const result = await resetOrderCounter({ archiveExisting });

    console.log('Current state:');
    console.log(`  Existing orders        : ${result.existingOrders}`);
    console.log(`  Highest orderNumber    : ${result.highestOrderNumber ?? '(none)'}`);
    console.log(`  Counter("orderNumber") : ${result.counter ?? '(not created yet)'}`);
    console.log('');
    console.log(result.message);

    if (!result.changed && result.existingOrders > 0) {
      console.log('');
      console.log('Nothing was changed.');
      console.log('To archive pre-launch/test orders and restart numbering at #1:');
      console.log('  node src/utils/resetOrderCounter.js --archive-existing');
    }
  } finally {
    await mongoose.disconnect();
  }
}

if (require.main === module) {
  main().catch(async (err) => {
    console.error('');
    console.error('========================================');
    console.error('RESET FAILED');
    console.error('========================================');
    console.error(err.message || err);
    try { await mongoose.disconnect(); } catch (_) {}
    process.exit(1);
  });
}

module.exports = { resetOrderCounter, ARCHIVE_OFFSET };
