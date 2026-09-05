const { Order, User, CreditTransaction } = require('../models');
const { asyncHandler } = require('../utils/apiError');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function dateRangeFilter(query) {
  const filter = {};
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) filter.createdAt.$gte = new Date(query.from);
    if (query.to) filter.createdAt.$lte = new Date(query.to);
  }
  return filter;
}

// GET /api/attendance/summary?from=&to=
// One row per employee: customers attended, orders handled, sales, and a
// breakdown by order type + credit transactions created. Only ever counts
// completed orders — cancelled/voided orders never count as attended sales.
const getAttendanceSummary = asyncHandler(async (req, res) => {
  const range = dateRangeFilter(req.query);
  const filter = { ...range, status: 'completed' };

  const [orderAgg, creditAgg] = await Promise.all([
    Order.aggregate([
      { $match: filter },
      {
        $group: {
          _id: '$staff',
          ordersHandled: { $sum: 1 },
          sales: { $sum: '$grandTotal' },
          dineIn: { $sum: { $cond: [{ $eq: ['$orderType', 'dine_in'] }, 1, 0] } },
          takeaway: { $sum: { $cond: [{ $eq: ['$orderType', 'takeaway'] }, 1, 0] } },
          delivery: { $sum: { $cond: [{ $eq: ['$orderType', 'delivery'] }, 1, 0] } },
          // "Customers attended" = distinct people served — dedupes repeat
          // visits from the same saved customer, falls back to one-per-order
          // for walk-ins with no saved customer record.
          customerKeys: { $addToSet: { $ifNull: ['$customer', '$_id'] } },
        },
      },
    ]),
    CreditTransaction.aggregate([
      { $match: dateRangeFilter(req.query) },
      { $group: { _id: '$recordedBy', count: { $sum: 1 } } },
    ]),
  ]);

  const creditMap = new Map(creditAgg.map((c) => [c._id.toString(), c.count]));
  const staffIds = orderAgg.map((o) => o._id).filter(Boolean);
  const staffDocs = await User.find({ _id: { $in: staffIds } }).select('name role');
  const staffMap = new Map(staffDocs.map((s) => [s._id.toString(), s]));

  const summary = orderAgg
    .filter((o) => o._id)
    .map((o) => {
      const staff = staffMap.get(o._id.toString());
      return {
        staffId: o._id,
        name: staff?.name || 'Unknown',
        role: staff?.role || 'staff',
        customersAttended: o.customerKeys.length,
        ordersHandled: o.ordersHandled,
        sales: round2(o.sales),
        dineIn: o.dineIn,
        takeaway: o.takeaway,
        delivery: o.delivery,
        creditTransactionsCreated: creditMap.get(o._id.toString()) || 0,
      };
    })
    .sort((a, b) => b.sales - a.sales);

  res.json({ success: true, data: summary });
});

// GET /api/attendance/:staffId?from=&to=
// Detailed activity for one employee: summary + the individual orders they
// attended, for the Admin drill-down view.
const getStaffAttendanceDetail = asyncHandler(async (req, res) => {
  const { staffId } = req.params;
  const range = dateRangeFilter(req.query);

  const staff = await User.findById(staffId).select('name role');

  const orders = await Order.find({ ...range, staff: staffId, status: 'completed' })
    .populate('customer', 'name')
    .populate('table', 'name')
    .sort({ createdAt: -1 });

  const dineIn = orders.filter((o) => o.orderType === 'dine_in').length;
  const takeaway = orders.filter((o) => o.orderType === 'takeaway').length;
  const delivery = orders.filter((o) => o.orderType === 'delivery').length;
  const sales = round2(orders.reduce((s, o) => s + o.grandTotal, 0));
  const customerKeys = new Set(orders.map((o) => (o.customer ? o.customer._id.toString() : o._id.toString())));

  res.json({
    success: true,
    data: {
      staff,
      summary: {
        customersAttended: customerKeys.size,
        ordersHandled: orders.length,
        sales,
        dineIn,
        takeaway,
        delivery,
      },
      orders: orders.map((o) => ({
        id: o._id,
        orderNumber: o.orderNumber,
        customerName: o.customer?.name || o.tableCustomerLabel || null,
        table: o.table?.name || null,
        orderType: o.orderType,
        grandTotal: o.grandTotal,
        createdAt: o.createdAt,
      })),
    },
  });
});

module.exports = { getAttendanceSummary, getStaffAttendanceDetail };
