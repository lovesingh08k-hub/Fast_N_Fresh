require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const { Order } = require('../models');

async function run() {
  await connectDB();
  const cursor = Order.find({ kitchenStatus: { $exists: false } }).cursor();
  let updated = 0;
  for await (const order of cursor) {
    const kitchenStatus = order.status === 'voided' || order.status === 'completed'
      ? 'served'
      : order.status === 'ready'
        ? 'ready'
        : order.status === 'preparing'
          ? 'preparing'
          : 'new';
    order.kitchenStatus = kitchenStatus;
    await order.save();
    updated += 1;
  }
  console.log(`Kitchen flow migration complete. Updated ${updated} order(s).`);
  await mongoose.connection.close();
}

run().catch(async (err) => {
  console.error(err);
  try { await mongoose.connection.close(); } catch (_) {}
  process.exit(1);
});
