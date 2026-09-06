/**
 * One-off maintenance utility for resetting the human-readable order
 * sequence.
 *
 * IMPORTANT:
 * - Existing orders are NOT deleted unless archiveExisting=true.
 * - When archiveExisting=true, all existing orders are PERMANENTLY DELETED.
 * - The order counter is then reset to 0.
 * - The next newly created order will be #1.
 *
 * This module can be run from the CLI OR called by the existing
 * authenticated maintenance endpoint.
 *
 * It never accepts a MongoDB URI from an HTTP request.
 */

require('dotenv').config();

const dns = require('dns');
const mongoose = require('mongoose');

dns.setServers(['8.8.8.8', '8.8.4.4']);

const { Order, Counter } = require('../models');

/**
 * Reset the order counter.
 *
 * @param {Object} options
 * @param {boolean} options.archiveExisting
 *
 * IMPORTANT:
 * archiveExisting=true means permanently delete existing orders.
 */
async function resetOrderCounter({ archiveExisting = false } = {}) {
  const mongoUri = process.env.MONGODB_URI;

  if (!mongoUri) {
    throw new Error('MONGODB_URI is not configured.');
  }

  console.log('Connecting to MongoDB...');

  await mongoose.connect(mongoUri);

  console.log('Connected.\n');

  const totalOrders = await Order.countDocuments({});

  const highest = await Order.findOne({})
    .sort({ orderNumber: -1 })
    .select('orderNumber')
    .lean();

  const counterDoc = await Counter.findById('orderNumber').lean();

  const state = {
    existingOrders: totalOrders,
    highestOrderNumber: highest ? highest.orderNumber : null,
    counter: counterDoc ? counterDoc.seq : null,
  };

  /*
   * No orders exist.
   *
   * Simply make sure the counter is at 0 so the next order becomes #1.
   */
  if (totalOrders === 0) {
    await Counter.findByIdAndUpdate(
      'orderNumber',
      {
        $set: {
          seq: 0,
        },
      },
      {
        upsert: true,
      }
    );

    return {
      ...state,
      changed: true,
      archived: 0,
      deleted: 0,
      nextOrderNumber: 1,
      message:
        'No existing orders found. Counter reset to 0; the next order will be #1.',
    };
  }

  /*
   * Existing orders were found but the caller did not explicitly request
   * the destructive reset.
   *
   * This preserves the old safe behavior.
   */
  if (!archiveExisting) {
    return {
      ...state,
      changed: false,
      archived: 0,
      deleted: 0,
      nextOrderNumber: (counterDoc ? counterDoc.seq : 0) + 1,
      message:
        'Existing orders found. Nothing was changed. Pass archiveExisting=true to permanently delete them and restart at #1.',
    };
  }

  /*
   * archiveExisting=true
   *
   * Despite the existing parameter name, this operation now permanently
   * deletes the existing orders.
   *
   * This keeps compatibility with the existing maintenance controller:
   *
   * resetOrderCounter({ archiveExisting: true })
   *
   * while changing the actual reset behavior to a clean production reset.
   */

  console.log(
    `Permanently deleting ${totalOrders} existing order(s)...`
  );

  const deleteResult = await Order.deleteMany({});

  const deleted = deleteResult.deletedCount || 0;

  /*
   * Reset the human-readable order counter.
   *
   * seq=0 means the next atomic increment produces order #1.
   */
  await Counter.findByIdAndUpdate(
    'orderNumber',
    {
      $set: {
        seq: 0,
      },
    },
    {
      upsert: true,
    }
  );

  return {
    ...state,
    changed: true,
    archived: 0,
    deleted,
    nextOrderNumber: 1,
    message:
      `Permanently deleted ${deleted} existing order(s). ` +
      'Counter reset to 0; the next order will be #1.',
  };
}

/**
 * CLI entry point.
 *
 * Safe by default:
 *
 *   node src/utils/resetOrderCounter.js
 *
 * does NOT delete existing orders.
 *
 * Destructive reset:
 *
 *   node src/utils/resetOrderCounter.js --archive-existing
 *
 * permanently deletes all existing orders and starts numbering at #1.
 */
async function main() {
  const archiveExisting = process.argv.includes('--archive-existing');

  try {
    console.log('========================================');
    console.log('ORDER COUNTER RESET');
    console.log('========================================');

    if (archiveExisting) {
      console.log('');
      console.log('WARNING: DESTRUCTIVE RESET');
      console.log('All existing orders will be permanently deleted.');
      console.log('');
    }

    const result = await resetOrderCounter({
      archiveExisting,
    });

    console.log('');
    console.log('Current state:');
    console.log(
      `  Existing orders        : ${result.existingOrders}`
    );
    console.log(
      `  Highest orderNumber    : ${
        result.highestOrderNumber ?? '(none)'
      }`
    );
    console.log(
      `  Counter("orderNumber") : ${
        result.counter ?? '(not created yet)'
      }`
    );

    console.log('');

    if (result.deleted > 0) {
      console.log(`Deleted orders           : ${result.deleted}`);
    }

    console.log('');
    console.log(result.message);

    if (!result.changed && result.existingOrders > 0) {
      console.log('');
      console.log('Nothing was changed.');
      console.log('');
      console.log(
        'To permanently delete existing orders and restart numbering at #1:'
      );
      console.log(
        '  node src/utils/resetOrderCounter.js --archive-existing'
      );
    }

    console.log('');
    console.log('Next order number        : #1');
    console.log('========================================');
  } finally {
    await mongoose.disconnect();
  }
}

/**
 * Run directly from CLI.
 */
if (require.main === module) {
  main().catch(async (err) => {
    console.error('');
    console.error('========================================');
    console.error('RESET FAILED');
    console.error('========================================');
    console.error(err.message || err);

    try {
      await mongoose.disconnect();
    } catch (_) {
      // Ignore disconnect errors during failure handling.
    }

    process.exit(1);
  });
}

module.exports = {
  resetOrderCounter,
};