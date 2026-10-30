const mongoose = require('mongoose');

// One row per business day, written before old bills are archived and
// deleted (see archiveController), so sales history and reports for those
// days stay available after the detailed records leave the database.
const dailySummarySchema = new mongoose.Schema(
  {
    businessDate: { type: String, required: true, unique: true }, // YYYY-MM-DD (IST)
    orders: { type: Number, default: 0 },
    voidedOrders: { type: Number, default: 0 },
    subtotal: { type: Number, default: 0 },
    discount: { type: Number, default: 0 },
    tax: { type: Number, default: 0 },
    netSales: { type: Number, default: 0 },
    refunds: { type: Number, default: 0 },
    expenses: { type: Number, default: 0 },
    payments: {
      cash: { type: Number, default: 0 },
      upi: { type: Number, default: 0 },
      card: { type: Number, default: 0 },
      credit: { type: Number, default: 0 },
      other: { type: Number, default: 0 },
    },
    byType: {
      dine_in: { type: Number, default: 0 },
      takeaway: { type: Number, default: 0 },
      delivery: { type: Number, default: 0 },
    },
    items: [
      {
        _id: false,
        name: { type: String, required: true },
        quantity: { type: Number, default: 0 },
        amount: { type: Number, default: 0 },
      },
    ],
  },
  { timestamps: true }
);

module.exports = mongoose.model('DailySummary', dailySummarySchema);
