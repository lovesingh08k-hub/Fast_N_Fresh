// Idempotent production menu migration for the requested Breakfast/Biryani split.
// Usage: npm run migrate:breakfast-biryani
//
// It reuses the existing Category/Product collections. Existing products are
// moved by name instead of recreated. Inventory/cost fields are never changed
// for existing products. New products are created only when missing.

require('dotenv').config();
const mongoose = require('mongoose');
const dns = require('dns');
const connectDB = require('../config/db');
const { Category, Product } = require('../models');

dns.setServers(['8.8.8.8', '8.8.4.4']);

const BREAKFAST = [
  ['Masala Dosa', 59],
  ['Idli Chutney', 49],
  ['Idli Fry', 69],
  ['Uttapam', 69],
  ['Aalu Paratha', 69],
  ['Methi Paratha', 69],
  ['Mix Veg Paratha', 79],
  ['Paneer Paratha', 99],
];

const BIRYANI = [
  ['Paneer Biryani', 129],
  ['Mix Veg Biryani', 109],
];

async function getOrCreateCategory(name, desiredOrder) {
  let category = await Category.findOne({ name });
  if (!category) {
    const max = await Category.findOne({}).sort({ sortOrder: -1 }).select('sortOrder');
    const next = Math.max(
      Number.isFinite(max?.sortOrder) ? max.sortOrder + 1 : 0,
      desiredOrder
    );
    category = await Category.create({ name, sortOrder: next, status: 'active' });
    console.log(`Created category: ${name} (sortOrder ${next})`);
  } else {
    console.log(`Using existing category: ${name} (sortOrder ${category.sortOrder})`);
  }
  return category;
}

async function ensureProduct(name, price, category) {
  const matches = await Product.find({ name }).sort({ isDeleted: 1, status: -1, createdAt: 1 });
  let product = matches.find((p) => !p.isDeleted) || matches[0];

  if (!product) {
    product = await Product.create({
      name,
      category: category._id,
      sellingPrice: price,
      // No stock/cost assumptions are applied to an existing product. For a
      // genuinely new menu item, inventory tracking starts disabled so a
      // migration cannot invent a stock quantity.
      costPrice: 0,
      trackInventory: false,
      stock: 0,
      lowStockThreshold: 10,
      status: 'available',
      isDeleted: false,
    });
    console.log(`Created product: ${name} @ ₹${price}`);
    return;
  }

  const changes = [];
  if (String(product.category) !== String(category._id)) {
    product.category = category._id;
    changes.push('category');
  }

  // Keep the requested menu price authoritative only when the product already
  // has the same named item; this migration is about the requested selling
  // prices as well as category placement.
  if (Number(product.sellingPrice) !== Number(price)) {
    product.sellingPrice = price;
    changes.push('sellingPrice');
  }

  if (changes.length) {
    await product.save();
    console.log(`Updated ${name}: ${changes.join(', ')}`);
  } else {
    console.log(`Verified product: ${name}`);
  }

  if (matches.filter((p) => !p.isDeleted).length > 1) {
    console.warn(`WARNING: multiple active/non-deleted products named "${name}" exist. No duplicate was created or deleted; review these records before consolidating them.`);
  }
}

async function run() {
  await connectDB();
  const breakfast = await getOrCreateCategory('Breakfast', 0);
  const biryani = await getOrCreateCategory('Biryani', 1);

  for (const [name, price] of BREAKFAST) await ensureProduct(name, price, breakfast);
  for (const [name, price] of BIRYANI) await ensureProduct(name, price, biryani);

  console.log('Breakfast/Biryani migration complete.');
}

run()
  .catch((error) => {
    console.error('Breakfast/Biryani migration failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try { await mongoose.connection.close(); } catch (_) {}
  });
