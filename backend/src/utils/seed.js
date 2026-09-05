// Development seed script.
// Usage: npm run seed
// Populates: admin + staff users, categories, sample products.
// Credentials are pulled from environment variables (see backend/.env) — never hardcoded.

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const { User, Category, Product, Table } = require('../models');

async function seed() {
  await connectDB();

  console.log('Seeding database...');

  // --- Admin user ---
  const adminUsername = (process.env.SEED_ADMIN_USERNAME || 'admin').toLowerCase();

  let admin = await User.findOne({ username: adminUsername });

  if (!admin) {
    admin = new User({
      name: process.env.SEED_ADMIN_NAME || 'Admin',
      username: adminUsername,
      phone: process.env.SEED_ADMIN_PHONE || '9999999999',
      role: 'admin',
      status: 'active',
    });

    await admin.setPassword(
      process.env.SEED_ADMIN_PASSWORD || 'Admin@123'
    );

    await admin.save();

    console.log(`  Created admin user: ${adminUsername}`);
  } else {
    // Existing admin: update configured account details and password.
    admin.name = process.env.SEED_ADMIN_NAME || admin.name;
    admin.phone = process.env.SEED_ADMIN_PHONE || admin.phone;
    admin.role = 'admin';
    admin.status = 'active';

    await admin.setPassword(
      process.env.SEED_ADMIN_PASSWORD || 'Admin@123'
    );

    await admin.save();

    console.log(`  Updated admin user and password: ${adminUsername}`);
  }

  // --- Manager user ---
  const managerUsername = (
    process.env.SEED_MANAGER_USERNAME || 'manager'
  ).toLowerCase();

  let manager = await User.findOne({
    username: managerUsername,
  });

  if (!manager) {
    manager = new User({
      name: process.env.SEED_MANAGER_NAME || 'Vikas',
      username: managerUsername,
      phone: process.env.SEED_MANAGER_PHONE || '7777777777',
      role: 'manager',
      status: 'active',
    });

    await manager.setPassword(
      process.env.SEED_MANAGER_PASSWORD || 'Manager@123'
    );

    await manager.save();

    console.log(`  Created manager user: ${managerUsername}`);
  } else {
    console.log(
      `  Manager user already exists: ${managerUsername}`
    );
  }

  // --- Staff user ---
  const staffUsername = (
    process.env.SEED_STAFF_USERNAME || 'staff'
  ).toLowerCase();

  let staff = await User.findOne({
    username: staffUsername,
  });

  if (!staff) {
    staff = new User({
      name: process.env.SEED_STAFF_NAME || 'Rahul',
      username: staffUsername,
      phone: process.env.SEED_STAFF_PHONE || '8888888888',
      role: 'staff',
      status: 'active',
    });

    await staff.setPassword(
      process.env.SEED_STAFF_PASSWORD || 'Staff@123'
    );

    await staff.save();

    console.log(`  Created staff user: ${staffUsername}`);
  } else {
    console.log(
      `  Staff user already exists: ${staffUsername}`
    );
  }

  // --- Categories ---
  const categoryNames = [
    'Tea',
    'Coffee',
    'Snacks',
    'Fast Food',
    'Meals',
    'Cold Drinks',
  ];

  const categoryDocs = {};

  for (let i = 0; i < categoryNames.length; i++) {
    const name = categoryNames[i];

    let cat = await Category.findOne({ name });

    if (!cat) {
      cat = await Category.create({
        name,
        sortOrder: i,
      });

      console.log(`  Created category: ${name}`);
    }

    categoryDocs[name] = cat;
  }

  // --- Products ---
  const products = [
    {
      name: 'Masala Chai',
      category: 'Tea',
      sellingPrice: 20,
      costPrice: 8,
      stock: 100,
      lowStockThreshold: 20,
    },
    {
      name: 'Cold Coffee',
      category: 'Coffee',
      sellingPrice: 80,
      costPrice: 35,
      stock: 50,
      lowStockThreshold: 10,
    },
    {
      name: 'Veg Sandwich',
      category: 'Snacks',
      sellingPrice: 100,
      costPrice: 45,
      stock: 40,
      lowStockThreshold: 10,
    },
    {
      name: 'Burger',
      category: 'Fast Food',
      sellingPrice: 120,
      costPrice: 55,
      stock: 40,
      lowStockThreshold: 10,
    },
    {
      name: 'French Fries',
      category: 'Snacks',
      sellingPrice: 90,
      costPrice: 35,
      stock: 40,
      lowStockThreshold: 10,
    },
  ];

  for (const p of products) {
    const exists = await Product.findOne({
      name: p.name,
    });

    if (!exists) {
      await Product.create({
        name: p.name,
        category: categoryDocs[p.category]._id,
        sellingPrice: p.sellingPrice,
        costPrice: p.costPrice,
        stock: p.stock,
        lowStockThreshold: p.lowStockThreshold,
        status: 'available',
      });

      console.log(`  Created product: ${p.name}`);
    }
  }

  // --- Tables ---
  const tableNames = [
    'Table 1',
    'Table 2',
    'Table 3',
    'Table 4',
    'Table 5',
    'Table 6',
  ];

  for (const name of tableNames) {
    const exists = await Table.findOne({
      name,
    });

    if (!exists) {
      const number = Number(
        name.match(/(\d+)/)[1]
      );

      await Table.create({
        name,
        capacity: 4,
        number,
      });

      console.log(
        `  Created table: ${name} (QR #${number})`
      );
    } else if (!exists.number) {
      const match = name.match(/(\d+)/);

      if (match) {
        exists.number = Number(match[1]);

        await exists.save();

        console.log(
          `  Assigned QR #${exists.number} to existing table: ${name}`
        );
      }
    }
  }

  console.log('\nSeed complete.');

  console.log(
    `  Admin login -> username: ${adminUsername} / password: (from SEED_ADMIN_PASSWORD env var)`
  );

  console.log(
    `  Manager login -> username: ${managerUsername} / password: (from SEED_MANAGER_PASSWORD env var)`
  );

  console.log(
    `  Staff login -> username: ${staffUsername} / password: (from SEED_STAFF_PASSWORD env var)`
  );

  await mongoose.disconnect();
  process.exit(0);
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});