const { Order, Product, Customer } = require('../models');
const { asyncHandler } = require('../utils/apiError');
const { BUSINESS_TIME_ZONE, startOfDay, endOfDay, daysAgo, startOfWeek, startOfMonth } = require('../utils/dateRanges');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

// The database adds these up, so the cost does not grow with the bills:
// the dashboard is refreshed all day on every device.
async function summarize(filter) {
  const [row] = await Order.aggregate([
    { $match: filter },
    {
      $group: {
        _id: null,
        sales: { $sum: '$grandTotal' },
        orders: { $sum: 1 },
        cash: { $sum: { $ifNull: ['$paymentBreakdown.cash', 0] } },
        upi: { $sum: { $ifNull: ['$paymentBreakdown.upi', 0] } },
        credit: { $sum: { $ifNull: ['$paymentBreakdown.credit', 0] } },
        card: { $sum: { $ifNull: ['$paymentBreakdown.card', 0] } },
        online: { $sum: { $ifNull: ['$paymentBreakdown.online', 0] } },
      },
    },
  ]);
  return {
    sales: round2(row?.sales || 0),
    orders: row?.orders || 0,
    cash: round2(row?.cash || 0),
    upi: round2(row?.upi || 0),
    credit: round2(row?.credit || 0),
    card: round2(row?.card || 0),
    online: round2(row?.online || 0),
  };
}

// GET /api/dashboard
const getDashboard = asyncHandler(async (req, res) => {
  const now = new Date();
  const todayStart = startOfDay(now);
  const todayEnd = endOfDay(now);

  // Completed orders drive sales/payment totals.
  const baseFilter = { status: 'completed', preLaunchTestData: { $ne: true } };
  if (req.user.role === 'staff') baseFilter.staff = req.user._id;

  // The dashboard's Orders card represents orders actually placed today,
  // not only bills already paid. QR orders start as `open`, so they must be
  // visible/countable immediately after the customer scans a table QR and
  // places the order. Voided orders are excluded. Staff also need unattended
  // QR orders even though those orders have no staff assigned yet.
  const placedTodayFilter = {
    status: { $ne: 'voided' },
    preLaunchTestData: { $ne: true },
    createdAt: { $gte: todayStart, $lte: todayEnd },
  };
  if (req.user.role === 'staff') {
    placedTodayFilter.$or = [
      { staff: req.user._id },
      { orderSource: 'qr', staff: { $exists: false } },
    ];
  }

  // Recent orders should include open QR orders too, otherwise the dashboard
  // looks unchanged until the customer reaches checkout. Only today's (IST)
  // orders are listed; earlier ones move to Yesterday/history in Bills.
  const recentOrdersFilter = {
    status: { $ne: 'voided' },
    preLaunchTestData: { $ne: true },
    createdAt: { $gte: todayStart, $lte: todayEnd },
  };
  if (req.user.role === 'staff') {
    recentOrdersFilter.$or = [
      { staff: req.user._id },
      { orderSource: 'qr', staff: { $exists: false } },
    ];
  }

  const [today, placedTodayCount, lowStockCount, outstandingAgg, recentOrders, topProductsAgg] = await Promise.all([
    summarize({ ...baseFilter, createdAt: { $gte: todayStart, $lte: todayEnd } }),
    Order.countDocuments(placedTodayFilter),
    Product.countDocuments({ isDeleted: false, trackInventory: true, $expr: { $lte: ['$stock', '$lowStockThreshold'] } }),
    Customer.aggregate([
      { $match: { outstandingBalance: { $gt: 0 } } },
      { $group: { _id: null, total: { $sum: '$outstandingBalance' }, count: { $sum: 1 } } },
    ]),
    Order.find(recentOrdersFilter)
      .select('orderNumber items.name items.quantity grandTotal paymentMethod status orderSource table createdAt')
      .populate('table', 'name number')
      .sort({ createdAt: -1 })
      .limit(10),
    Order.aggregate([
      { $match: { ...baseFilter, createdAt: { $gte: daysAgo(30) } } },
      { $unwind: '$items' },
      { $group: { _id: '$items.name', qty: { $sum: '$items.quantity' } } },
      { $sort: { qty: -1 } },
      { $limit: 5 },
    ]),
  ]);

  // Keep sales/payment totals based on completed bills, but expose the number
  // of all placed (non-voided) orders and operational alerts for the manager.
  today.orders = placedTodayCount;
  const cancelledToday = await Order.countDocuments({status:'voided',createdAt:{ $gte: todayStart, $lte: todayEnd }});
  const pendingPaymentsToday = await Order.countDocuments({status:{ $nin:['completed','voided'] },paymentStatus:{ $ne:'paid' },createdAt:{ $gte:todayStart,$lte:todayEnd }});
  const outstanding = outstandingAgg[0] || { total: 0, count: 0 };

  res.json({
    success: true,
    data: {
      today,
      lowStockCount,
      // Unbilled orders right now (tables, counters, QR): count and value.
      running: await Order.aggregate([
        { $match: { status: { $in: ['open', 'preparing', 'ready'] }, paymentStatus: { $ne: 'paid' } } },
        { $group: { _id: null, count: { $sum: 1 }, value: { $sum: '$grandTotal' }, ready: { $sum: { $cond: [{ $eq: ['$status', 'ready'] }, 1, 0] } } } },
      ]).then((r) => ({ count: r[0]?.count || 0, value: Math.round((r[0]?.value || 0) * 100) / 100, ready: r[0]?.ready || 0 })),
      outstandingCredit: { total: round2(outstanding.total), customerCount: outstanding.count },
      cancelledToday,
      pendingPaymentsToday,
      recentOrders: recentOrders.map((o) => ({
        orderNumber: o.orderNumber,
        itemsSummary: o.items.map((i) => `${i.quantity} ${i.name}`).join(', '),
        grandTotal: o.grandTotal,
        // Preserve the actual order lifecycle. Completed orders must never
        // fall through to the QR "new" presentation in the mobile client.
        paymentMethod: o.paymentMethod || (o.status === 'completed' ? '—' : (o.orderSource === 'qr' ? 'UNPAID' : 'PENDING')),
        status: String(o.status || 'completed').trim().toLowerCase(),
        orderSource: o.orderSource,
        tableName: o.table?.name,
        createdAt: o.createdAt,
      })),
      topSellingProducts: topProductsAgg.map((p) => ({ name: p._id, quantitySold: p.qty })),
    },
  });
});

// GET /api/dashboard/sales-overview — Today / Yesterday / Week / Month + daily graph data
const getSalesOverview = asyncHandler(async (req, res) => {
  const now = new Date();
  const baseFilter = { status: 'completed', preLaunchTestData: { $ne: true } };
  if (req.user.role === 'staff') baseFilter.staff = req.user._id;

  const yesterday = daysAgo(1);

  const [today, yesterdayTotals, thisWeek, thisMonth, graphData] = await Promise.all([
    summarize({ ...baseFilter, createdAt: { $gte: startOfDay(now), $lte: endOfDay(now) } }),
    summarize({ ...baseFilter, createdAt: { $gte: startOfDay(yesterday), $lte: endOfDay(yesterday) } }),
    summarize({ ...baseFilter, createdAt: { $gte: startOfWeek(now) } }),
    summarize({ ...baseFilter, createdAt: { $gte: startOfMonth(now) } }),
    Order.aggregate([
      { $match: { ...baseFilter, createdAt: { $gte: startOfDay(daysAgo(13)) } } },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: BUSINESS_TIME_ZONE } },
          sales: { $sum: '$grandTotal' },
          orders: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ]),
  ]);

  res.json({
    success: true,
    data: {
      today,
      yesterday: yesterdayTotals,
      thisWeek,
      thisMonth,
      last14Days: graphData.map((d) => ({ date: d._id, sales: round2(d.sales), orders: d.orders })),
    },
  });
});

module.exports = { getDashboard, getSalesOverview };
