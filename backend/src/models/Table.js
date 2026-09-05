const mongoose = require('mongoose');

// Represents a physical dine-in table. `status` is mostly system-managed
// (occupied/available flip automatically as open orders come and go — see
// orderController) but can also be set manually to 'reserved' by staff.
const tableSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true }, // e.g. "Table 1"
    // Numeric identifier used in customer-facing QR ordering URLs, e.g.
    // /menu?table=5. Optional/sparse so existing tables keep working before
    // a number is assigned; enforced unique among tables that have one set.
    number: { type: Number, min: 1, unique: true, sparse: true },
    capacity: { type: Number, default: 4, min: 1 },
    status: { type: String, enum: ['available', 'occupied', 'reserved'], default: 'available' },
    active: { type: Boolean, default: true }, // soft delete/deactivate — never hard-delete a table with order history
  },
  { timestamps: true }
);

tableSchema.index({ active: 1, status: 1 });

module.exports = mongoose.model('Table', tableSchema);
