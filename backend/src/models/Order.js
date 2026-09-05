const mongoose = require('mongoose');

// OrderItem is embedded as a sub-document of Order. This keeps order creation
// atomic and avoids extra round trips, while still being a clearly defined,
// independently validated schema (satisfies the OrderItem model requirement).
const orderItemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
    name: { type: String, required: true }, // snapshot at time of sale
    price: { type: Number, required: true, min: 0 }, // snapshot selling price at time of sale
    quantity: { type: Number, required: true, min: 1 },
    total: { type: Number, required: true, min: 0 },
  },
  { _id: false }
);

const orderSchema = new mongoose.Schema(
  {
    orderNumber: { type: Number, required: true, unique: true }, // sequential, human-readable; unique:true already builds the index

    // Idempotency guard. The Flutter app generates one UUID per checkout
    // attempt (persisted for the lifetime of that bill/payment sheet) and
    // sends it as `clientRequestId`. If a request is retried after a
    // timeout/dropped response — a double-tap the frontend didn't prevent,
    // or a manual "Retry" after a lost response on a Render cold start —
    // the unique index below makes a second insert with the same id fail
    // with a duplicate-key error instead of creating a second order/charge.
    // The controller catches that and returns the original order instead.
    // Sparse so it never applies to legacy/undefined values.
    clientRequestId: { type: String, index: { unique: true, sparse: true } },

    items: { type: [orderItemSchema], required: true, default: [] },

    // Order type: which channel this order came through.
    orderType: { type: String, enum: ['dine_in', 'takeaway', 'delivery'], default: 'takeaway', index: true },
    // Where the order originated. 'qr' orders are placed by a customer via
    // the public /menu page (no logged-in user) and start unattended; 'pos'
    // covers every existing staff-entered order (unchanged default).
    orderSource: { type: String, enum: ['pos', 'qr'], default: 'pos', index: true },
    // Only set for dine_in orders. References the physical Table.
    table: { type: mongoose.Schema.Types.ObjectId, ref: 'Table' },
    // Distinguishes multiple simultaneous customers/orders on the same table
    // (e.g. "Customer 1", "Customer 2"). Purely a display label.
    tableCustomerLabel: { type: String, trim: true },
    // Contact info a customer optionally gives when placing a QR order
    // directly (no account/login). Not used by POS-entered orders.
    qrCustomerContact: {
      name: { type: String, trim: true },
      phone: { type: String, trim: true },
    },
    // Only used for orderType = 'delivery'. Reuses the existing Customer
    // system where possible (see `customer` field below) — these fields
    // exist for delivery-specific details or walk-in delivery without a
    // saved Customer record.
    deliveryInfo: {
      address: { type: String, trim: true },
      phone: { type: String, trim: true },
    },

    subtotal: { type: Number, required: true, min: 0, default: 0 },
    discount: { type: Number, default: 0, min: 0 },
    tax: { type: Number, default: 0, min: 0 },
    grandTotal: { type: Number, required: true, min: 0, default: 0 },

    paymentMethod: { type: String, enum: ['CASH', 'UPI', 'CREDIT', 'MIXED'] },
    // Payment state is deliberately separate from kitchen/order state.
    // QR orders begin pending and become paid only at trusted staff checkout.
    //   pending            - CASH (pay-at-counter) order, or not yet started.
    //   payment_initiated  - customer tapped "Pay with UPI" and was handed
    //                        off to a UPI app. NOT proof of payment — only
    //                        that an attempt started. Set the moment the
    //                        order is created for paymentMethod=UPI.
    //   paid               - verified paid. Only ever set by an authenticated
    //                        staff member at checkout (see orderController),
    //                        after they've confirmed the money actually
    //                        arrived. Never set automatically from the
    //                        public/customer-facing endpoints.
    //   failed             - a payment attempt that is known not to have
    //                        gone through (reserved for future PSP webhook
    //                        integration; unused today).
    //   cancelled          - customer or staff cancelled before payment.
    paymentStatus: {
      type: String,
      enum: ['pending', 'payment_initiated', 'paid', 'failed', 'cancelled'],
      default: 'pending',
      index: true,
    },
    // Set when paymentStatus first becomes 'payment_initiated'. Lets staff
    // see (and, if needed, clean up/cancel) UPI orders where the customer
    // opened a UPI app but never returned to submit a reference.
    paymentInitiatedAt: { type: Date },
    paymentBreakdown: {
      cash: { type: Number, default: 0 },
      upi: { type: Number, default: 0 },
      credit: { type: Number, default: 0 },
    },
    upiReference: { type: String, trim: true },
    amountReceived: { type: Number }, // for cash, amount tendered
    changeReturned: { type: Number, default: 0 },

    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer' }, // required only for CREDIT/MIXED-with-credit, or delivery customer
    notes: { type: String, trim: true },

    // The staff/manager/admin who is handling this order ("attendedBy").
    // Automatically set to the authenticated user at order-start time —
    // never entered manually. Kept as `staff` for backward compatibility
    // with the existing schema/reports; new code should read this as
    // "attendedBy". A QR order has no logged-in user when the customer
    // places it, so it starts with no staff and gets attributed to whoever
    // checks it out (see orderController.checkoutOrder).
    staff: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: function () {
        return this.orderSource !== 'qr';
      },
    },
    // Optional handover trail if a different employee takes over the same
    // customer/order before it's completed. Most orders will have none.
    attendedByHistory: [
      {
        user: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        from: { type: Date },
        to: { type: Date },
      },
    ],

    status: { type: String, enum: ['open', 'preparing', 'ready', 'completed', 'voided'], default: 'completed' },
    estimatedReadyAt: { type: Date },
    voidedAt: { type: Date },
    voidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    voidReason: { type: String, trim: true },
  },
  { timestamps: true }
);

orderSchema.index({ createdAt: -1 });
orderSchema.index({ staff: 1, createdAt: -1 });
orderSchema.index({ customer: 1, createdAt: -1 });
orderSchema.index({ paymentMethod: 1 });
orderSchema.index({ table: 1, status: 1 });
orderSchema.index({ orderType: 1, createdAt: -1 });

module.exports = mongoose.model('Order', orderSchema);
