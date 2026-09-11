// One-off migration:
// Assign a QR ordering number to every Table that does not have one.
//
// Examples:
//   "Table 1"      -> number: 1
//   "Table 2"      -> number: 2
//   "Table No. 3"  -> number: 3
//   "Table-15"     -> number: 15
//
// IMPORTANT:
// - Only tables missing `number` are changed.
// - Existing numbers are never changed.
// - Active/inactive status is never changed.
// - If the extracted number is already used, the table is skipped.
// - If a table name has no number, it is skipped.
//
// Run:
//   node src/utils/migrateTableNumbers.js

require('dotenv').config();

const dns = require('dns');
const mongoose = require('mongoose');

const { Table } = require('../models');

// -----------------------------------------------------------------------------
// MongoDB Atlas DNS FIX
// -----------------------------------------------------------------------------
// On this Windows/network setup, Node's default DNS resolver is returning:
//
//   querySrv ECONNREFUSED _mongodb._tcp.cluster0.dngmyml.mongodb.net
//
// Google DNS successfully resolves the MongoDB Atlas SRV record, so explicitly
// use Google DNS for this one-off migration.
// -----------------------------------------------------------------------------

dns.setServers([
  '8.8.8.8',
  '8.8.4.4',
]);

async function migrate() {
  try {
    // -------------------------------------------------------------------------
    // 1. Validate MongoDB URI
    // -------------------------------------------------------------------------

    const mongoUri = process.env.MONGODB_URI;

    if (!mongoUri) {
      throw new Error(
        'MONGODB_URI is not configured.'
      );
    }

    if (!mongoUri.startsWith('mongodb+srv://')) {
      throw new Error(
        'MONGODB_URI must be a MongoDB Atlas mongodb+srv:// connection string.'
      );
    }

    console.log('Connecting to MongoDB...');

    // -------------------------------------------------------------------------
    // 2. Connect directly to production MongoDB Atlas
    // -------------------------------------------------------------------------

    await mongoose.connect(mongoUri);

    console.log('Connected to MongoDB.');
    console.log('');

    // -------------------------------------------------------------------------
    // 3. Find tables without QR numbers
    // -------------------------------------------------------------------------

    const tables = await Table.find({
      $or: [
        {
          number: {
            $exists: false,
          },
        },
        {
          number: null,
        },
      ],
    }).sort({
      name: 1,
    });

    console.log(
      `Found ${tables.length} table(s) without a QR number.`
    );

    console.log('');

    let assigned = 0;
    let skipped = 0;

    // -------------------------------------------------------------------------
    // 4. Process every table
    // -------------------------------------------------------------------------

    for (const table of tables) {
      const tableName = String(
        table.name || ''
      ).trim();

      // -----------------------------------------------------------------------
      // Missing table name
      // -----------------------------------------------------------------------

      if (!tableName) {
        console.warn(
          `SKIP: Table ${table._id} has no name.`
        );

        skipped++;

        continue;
      }

      // -----------------------------------------------------------------------
      // Extract number from table name
      //
      // Examples:
      // "Table 1"       -> 1
      // "Table 2"       -> 2
      // "Table No. 3"   -> 3
      // "Table-15"      -> 15
      // "ABC 20 Table"  -> 20
      // -----------------------------------------------------------------------

      const match = tableName.match(
        /(\d+)/
      );

      if (!match) {
        console.warn(
          `SKIP: "${tableName}" has no number in its name.`
        );

        skipped++;

        continue;
      }

      const candidate = Number(
        match[1]
      );

      // -----------------------------------------------------------------------
      // Validate extracted number
      // -----------------------------------------------------------------------

      if (
        !Number.isInteger(candidate) ||
        candidate < 1
      ) {
        console.warn(
          `SKIP: "${tableName}" produced invalid QR number: ${candidate}`
        );

        skipped++;

        continue;
      }

      // -----------------------------------------------------------------------
      // Check if QR number is already used by another table
      // -----------------------------------------------------------------------

      const existingTable = await Table.findOne({
        number: candidate,
        _id: {
          $ne: table._id,
        },
      }).select(
        '_id name number'
      );

      if (existingTable) {
        console.warn(
          `SKIP: "${tableName}" -> QR #${candidate} is already used by "${existingTable.name}".`
        );

        skipped++;

        continue;
      }

      // -----------------------------------------------------------------------
      // Assign QR number
      // -----------------------------------------------------------------------

      table.number = candidate;

      await table.save();

      console.log(
        `OK: "${tableName}" -> QR #${candidate}`
      );

      assigned++;
    }

    // -------------------------------------------------------------------------
    // 5. Migration summary
    // -------------------------------------------------------------------------

    console.log('');

    console.log(
      '======================================'
    );

    console.log(
      'QR TABLE NUMBER MIGRATION COMPLETE'
    );

    console.log(
      '======================================'
    );

    console.log(
      `Assigned : ${assigned}`
    );

    console.log(
      `Skipped  : ${skipped}`
    );

    console.log('');

    // -------------------------------------------------------------------------
    // 6. Show final production table state
    // -------------------------------------------------------------------------

    const allTables = await Table.find({})
      .select(
        '_id name number active'
      )
      .sort({
        number: 1,
        name: 1,
      })
      .lean();

    console.log(
      'Current production tables:'
    );

    console.log('');

    console.table(
      allTables.map((table) => ({
        name: table.name,
        number: table.number ?? '-',
        active: table.active ?? true,
      }))
    );

    // -------------------------------------------------------------------------
    // 7. Disconnect
    // -------------------------------------------------------------------------

    await mongoose.disconnect();

    console.log('');

    console.log(
      'MongoDB disconnected.'
    );

    console.log(
      'Migration finished successfully.'
    );

    process.exit(0);

  } catch (error) {
    // -------------------------------------------------------------------------
    // Error handling
    // -------------------------------------------------------------------------

    console.error('');

    console.error(
      'Migration failed:'
    );

    console.error(
      error.message || error
    );

    try {
      await mongoose.disconnect();
    } catch (_) {
      // Ignore disconnect errors.
    }

    process.exit(1);
  }
}

// -----------------------------------------------------------------------------
// Start migration
// -----------------------------------------------------------------------------

migrate();