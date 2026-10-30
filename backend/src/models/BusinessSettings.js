const mongoose = require('mongoose');

// Singleton document holding cafe-wide configuration.
const businessSettingsSchema = new mongoose.Schema(
  {
    singletonKey: { type: String, default: 'MAIN', unique: true },

    cafeName: { type: String, default: 'PWP POS • PERSONALIZE WEB PAGE' },
    tagline: { type: String, default: 'Fresh • Fast • Delicious' },
    phone: { type: String, default: '' },
    address: { type: String, default: '' },
    gstNumber: { type: String, default: '' },
    logoUrl: { type: String, default: '' },
    upiId: { type: String, default: '' },

    receiptFooter: { type: String, default: 'Thank you for visiting!\nVisit Again' },
    taxEnabled: { type: Boolean, default: false },
    taxPercent: { type: Number, default: 0, min: 0, max: 100 },
    defaultDiscount: { type: Number, default: 0, min: 0 },
    currencySymbol: { type: String, default: '₹' },

    primaryColor: { type: String, default: '#0E7C5A' },

    // ---- Billing (see services/billing.js)
    // taxPercent above is the default GST rate (items can have their own);
    // gstNumber is the GSTIN printed on the bill.
    taxInclusive: { type: Boolean, default: false }, // menu prices already include GST
    gstType: { type: String, enum: ['cgst_sgst', 'igst'], default: 'cgst_sgst' },
    fssai: { type: String, trim: true, default: '' },
    invoicePrefix: { type: String, trim: true, default: 'INV' },
    roundOff: { type: Boolean, default: true }, // round the bill to the nearest rupee
    serviceChargePercent: { type: Number, default: 0, min: 0, max: 30 },
    serviceChargeOn: { type: [String], default: ['dine_in'] },
    packagingCharge: { type: Number, default: 0, min: 0 },
    packagingChargeOn: { type: [String], default: ['takeaway', 'delivery'] },
    deliveryCharge: { type: Number, default: 0, min: 0 },
    // Delivery apps whose orders are billed as "Online" payments.
    onlinePlatforms: { type: [String], default: ['Swiggy', 'Zomato'] },

    // Last time old records were exported and deleted (archiveController).
    lastArchiveAt: { type: Date, default: null },

    // Takeaway (T1, T2...) and Delivery (D1, D2...) counters shown like
    // dine-in tables. Managed through /api/counters, not updateSettings.
    takeawayCounters: { type: [Number], default: [1, 2, 3, 4] },
    deliveryCounters: { type: [Number], default: [1, 2, 3, 4] },
  },
  { timestamps: true }
);

// Optional `session` lets order-pricing code read settings consistently
// within the same transaction it's pricing an order under.
businessSettingsSchema.statics.getSettings = async function getSettings(session) {
  const query = this.findOne({ singletonKey: 'MAIN' });
  if (session) query.session(session);
  let settings = await query;
  if (!settings) {
    const created = await this.create([{ singletonKey: 'MAIN' }], session ? { session } : undefined);
    settings = created[0];
  }
  return settings;
};

module.exports = mongoose.model('BusinessSettings', businessSettingsSchema);
