// Menu/inventory import script — populates the EXISTING Category/Product/
// InventoryTransaction models with the items from
// "Fast N Fresh Cafe Menu_20250505_181019_0000.pdf" (the customer's menu PDF,
// used as the source of truth for TASK 1 — "fill inventory from my PDF").
//
// This does NOT create a new inventory system. It reuses the same models
// and the same fields that productController.createProduct() and
// inventoryController already use, and follows the same idempotent
// "skip if it already exists" pattern as the existing src/utils/seed.js.
//
// Usage: npm run seed:menu
//
// IMPORTANT — assumption made explicit here (the PDF is a printed customer
// menu, not a stock-count sheet): it lists item names and selling prices
// only, with no stock quantities or cost prices. Every imported product is
// therefore created with:
//   - costPrice: 0
//   - stock: DEFAULT_INITIAL_STOCK
//   - lowStockThreshold: 10
//   - trackInventory: true
//   - status: 'available'
//
// Categories are the PDF's own section headings.
//
// One name collision existed in the source PDF itself: "Manchurian Momos"
// is printed twice with two different prices (99 under "Momos", 109 under
// "Kurkure Momos"). To avoid creating a duplicate product with the same
// name, the second one is imported as "Manchurian Kurkure Momos".

require('dotenv').config();

// IMPORTANT:
// The main app already uses Google DNS to reliably resolve the
// MongoDB Atlas SRV record. The seed script must do the same.
const dns = require('dns');

dns.setServers([
  '8.8.8.8',
  '8.8.4.4',
]);

const mongoose = require('mongoose');
const connectDB = require('../config/db');

const {
  User,
  Category,
  Product,
  InventoryTransaction,
} = require('../models');

const DEFAULT_INITIAL_STOCK = 30;
const DEFAULT_LOW_STOCK_THRESHOLD = 10;

// [categoryName, [[productName, sellingPrice], ...]]
const MENU = [
  ['Pizza', [
    ['Margrita pizza', 120],
    ['Single Topping Pizza', 129],
    ['BBQ Mushroom Pizza', 129],
    ["Farmer's Choice Pizza", 149],
    ['Veg Supreme Pizza', 159],
    ['Cheesy Mushroom And Corn Pizza', 159],
    ['BBQ Paneer and Onion Pizza', 179],
    ['Schezwan Paneer Pizza', 179],
    ['Tandoori Paneer Pizza', 179],
    ['Peri Peri Paneer Pizza', 179],
    ['Paneer Makhani Pizza', 179],
    ['Cheese Burst Pizza', 249],
  ]],

  ['Chocolate Milkshake', [
    ['Chocolate Brownie Milkshake', 119],
    ['Chocolate Choco-Chip Milkshake', 99],
    ['Chocolate Oreo Milkshake', 99],
    ['Choco Crunchy Peanut', 99],
    ['Kit-Kat Milkshake', 99],
    ['Chocolate Caramel Milkshake', 99],
    ['Roasted Hazelnut Milkshake', 99],
  ]],

  ['Traditional Cold Coffee', [
    ['Regular Cold Coffee', 89],
    ['Vanila Cold Coffee', 89],
    ['Caramel Cold Coffee', 99],
    ['Chocolate Cold Coffee', 99],
    ['Cold Coffee With Ice Cream', 119],
  ]],

  ['Flavoured Milkshake', [
    ['Biscoff Milkshake', 99],
    ['Tutti Frutti Milkshake', 89],
    ['Butterscotch Milkshake', 89],
    ['Mango Milkshake', 89],
    ['Paan Delight Milkshake', 89],
    ['BubbleGum Milkshake', 89],
    ['Tangy Kesar Milkshake', 89],
  ]],

  ['Burger Menu', [
    ['Aloo Tikki Burger', 49],
    ['Veg Tikki burger', 69],
    ['Double Cheese Burger', 89],
    ['Tandoori Paneer Burger', 99],
    ['Schezwan paneer Burger', 99],
    ['Double Patty Burger', 109],
    ['Double Patty with Double cheese Burger', 129],
  ]],

  ['Desi Mocktails', [
    ['Lemon Ice Tea', 79],
    ['Peach Ice Tea', 79],
    ['Jal Jeera Mocktail', 79],
    ['Classic Virgin Mojito', 89],
    ['Green Apple Mojito', 89],
    ['Blue Lagoon Mocktail', 89],
    ['Raspberry Mocktail', 89],
    ['Mango Mocktail', 89],
    ['Paan Bahar Mocktail', 89],
  ]],

  ['Summer Special Drinks', [
    ['Dryfruit Lassi', 89],
    ['Thandai Shake', 89],
    ['Roohafza Shake', 89],
    ['Mango Lassi', 79],
    ['Paan Lassi', 79],
  ]],

  ['French Fries', [
    ['Salted / Pepper Fries', 79],
    ['Peri Peri Fries', 89],
    ['Cheese Fries', 99],
    ['FNF Special Fries', 119],
  ]],

  ['Momos', [
    ['Veg Momos', 90],
    ['Paneer Momos', 110],
    ['Manchurian Momos', 99],
  ]],

  ['Kurkure Momos', [
    ['Veg Kurkure Momos', 99],
    ['Paneer Kurkure Momos', 119],
    ['Manchurian Kurkure Momos', 109],
  ]],

  ['Vocal For Local', [
    ['Hot Chocolate', 60],
    ['Hot Coffee', 20],
    ['Hot Tea', 20],
    ['Lemon Tea', 15],
  ]],

  ['Maggie Magic', [
    ['Plain Maggie', 59],
    ['Plain Cheese Maggie', 69],
    ['Masala Maggie', 69],
    ['Special Cheese Maggie', 79],
    ['Cheese Corn Maggie', 79],
    ['Vegitable Maggie', 89],
    ['Vegitable Cheese Maggie', 109],
    ['Vegitable Creamy Maggie', 129],
  ]],

  ['Sandwiches', [
    ['Veg Mayo Sandwich', 89],
    ['Veg Schezwan Sandwich', 99],
    ['Cheese Corn Sandwich', 99],
    ['Paneer Corn Cheese Sandwich', 119],
    ['Paneer Cheese Sandwich', 109],
    ['Peri peri paneer Sandwich', 109],
    ['Paneer Makhani Sandwich', 109],
    ['Tandoori Paneer Sandwich', 109],
    ['Schezwan paneer Sandwich', 109],
  ]],

  ['Penne Pasta', [
    ['Red sauce pasta', 129],
    ['White sauce pasta', 139],
    ['Mixed sauce pasta', 149],
    ['Freshly Baked Pasta', 179],
  ]],

  ['Veg Appetizers', [
    ['Veg Nuggets (8 Pieces)', 89],
    ['Veg Fingers (6 pieces)', 99],
    ['Chili Garli Photato Pops (12 Pieces)', 99],
    ['Cheese Garlic Bread (4 Pieces)', 109],
    ['Cheese Corn Nuggets (8 Pieces)', 109],
    ['Cheese photatpo Pops (12 Pieces)', 109],
  ]],

  ['Veg Wraps', [
    ['veg aloo Wrap', 69],
    ['veg aloo cheese Wrap', 79],
    ['cheese corn wrap', 79],
    ['Paneer Cheese Wrap', 99],
    ['Schezwan Paneer Wrap', 109],
    ['Schezwan Paneer cheese wrap', 119],
    ['Peri Peri Paneer Wrap', 99],
    ['Peri Peri Paneer Cheese wrap', 119],
    ['Tandoori Paneer Wrap', 99],
    ['Tandoori Paneer Cheese Wrap', 119],
    ['Paneer Makhani Wrap', 99],
    ['Paneer Makhani Cheese Wrap', 119],
  ]],

  ['Desserts', [
    ['Choco-Lava Cake with Vanilla Ice Cream', 99],
    ['Choco-Lava Cake', 69],
    ['Chocolate Brownie with vanilla ice cream', 99],
    ['Chocoilate Brownie', 69],
    ['Mix Ice Cream', 99],
    ['Chocolate Ice-Cream', 59],
    ['Butterscotch Ice Cream', 59],
    ['Vanilla Ice-Cream', 59],
  ]],

  ['Chinese Veg Starters', [
    ['Honey Chilli Photato', 149],
    ['Cripy Corn', 129],
    ['Corn Chilli', 149],
    ['Gobhi Chilli', 149],
    ['Chinese Bhel', 149],
    ['Veg Crispy', 169],
    ['Paneer Chilly', 169],
    ['Paneer Crispy', 169],
    ['Chana Chilli', 149],
    ['Chana Crispy', 149],
    ['Veg Manchurian', 149],
    ['Mushroom Chilli', 169],
  ]],

  ['Chinese Veg Soups', [
    ['Veg Manchow Soup', 79],
    ['Veg Schezwan Soup', 79],
    ['Sweet Corn Soup', 79],
    ['Burnt Garlic Soup', 79],
    ['Tomato Soup', 79],
  ]],

  ['Veg Rolls', [
    ['Veg Roll', 79],
    ['Veg Manchurian Roll', 89],
    ['Veg Noodles Roll', 99],
    ['Paneer Roll', 109],
    ['paneer cheese Roll', 129],
  ]],

  ['Veg Rice', [
    ['Veg fried rice', 120],
    ['Masala Rice', 120],
    ['Veg schezwan fried rice', 149],
    ['veg Manchurian fried rice', 149],
    ['Veg Schezwan tripal fried rice', 189],
    ['paneer fried rice', 189],
    ['paneer chilli fried rice', 199],
    ['Mushroom Fried rice', 169],
  ]],

  ['Veg Noodles', [
    ['Veg Hakka Noodles', 120],
    ['Veg Schezwan Noodles', 149],
    ['Veg manchurian Noodles', 149],
    ['Mushroom Noodles', 149],
    ['Tripal Schezwan Noodles', 149],
    ['Paneer Noodles', 149],
    ['Veg Chowmin', 99],
    ['Veg Schezwan Chowmin', 129],
    ['Panner Chowmin', 149],
    ['Paneer Schezwan Chowmin', 179],
  ]],
];

async function seedMenu() {
  await connectDB();

  console.log('Importing menu/inventory from PDF...');

  // Attribute initial-stock transactions to an existing admin/manager user.
  const recordedBy =
    (await User.findOne({ role: 'admin' })) ||
    (await User.findOne({ role: 'manager' })) ||
    (await User.findOne({}));

  if (!recordedBy) {
    console.log(
      'Note: no existing user found — products will be created without an initial-stock InventoryTransaction log entry.'
    );
  }

  let categoriesCreated = 0;
  let productsCreated = 0;
  let productsSkipped = 0;

  for (let sortOrder = 0; sortOrder < MENU.length; sortOrder++) {
    const [categoryName, items] = MENU[sortOrder];

    let category = await Category.findOne({
      name: categoryName,
    });

    if (!category) {
      category = await Category.create({
        name: categoryName,
        sortOrder,
      });

      categoriesCreated++;

      console.log(`Created category: ${categoryName}`);
    }

    for (const [name, sellingPrice] of items) {
      const escapedName = name.replace(
        /[.*+?^${}()|[\]\\]/g,
        '\\$&'
      );

      const exists = await Product.findOne({
        name: new RegExp(`^${escapedName}$`, 'i'),
      });

      if (exists) {
        productsSkipped++;
        continue;
      }

      const product = await Product.create({
        name,
        category: category._id,
        sellingPrice,
        costPrice: 0,
        stock: DEFAULT_INITIAL_STOCK,
        lowStockThreshold: DEFAULT_LOW_STOCK_THRESHOLD,
        trackInventory: true,
        status: 'available',
      });

      productsCreated++;

      if (recordedBy) {
        await InventoryTransaction.create({
          product: product._id,
          type: 'STOCK_IN',
          quantity: DEFAULT_INITIAL_STOCK,
          stockAfter: DEFAULT_INITIAL_STOCK,
          reason: 'Initial stock — imported from menu PDF',
          recordedBy: recordedBy._id,
        });
      }

      console.log(
        `Created product: ${name} (₹${sellingPrice}) [${categoryName}]`
      );
    }
  }

  console.log('\nMenu import complete.');
  console.log(`Categories created: ${categoriesCreated}`);
  console.log(`Products created:   ${productsCreated}`);
  console.log(`Products skipped (already existed): ${productsSkipped}`);

  await mongoose.disconnect();
  process.exit(0);
}

seedMenu().catch((err) => {
  console.error('Menu import failed:', err);
  process.exit(1);
});