const { Order, Customer, Expense, User } = require('../models');
const { asyncHandler } = require('../utils/apiError');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function parseRange(query) {
  const filter = { status: 'completed' };
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) filter.createdAt.$gte = new Date(query.from);
    if (query.to) filter.createdAt.$lte = new Date(query.to);
  }
  return filter;
}

// GET /api/reports/sales?from=&to=
const getSalesReport = asyncHandler(async (req, res) => {
  const filter = parseRange(req.query);
  const orders = await Order.find(filter);

  const totalSales = orders.reduce((s, o) => s + o.grandTotal, 0);
  const cash = orders.reduce((s, o) => s + (o.paymentBreakdown?.cash || 0), 0);
  const upi = orders.reduce((s, o) => s + (o.paymentBreakdown?.upi || 0), 0);
  const credit = orders.reduce((s, o) => s + (o.paymentBreakdown?.credit || 0), 0);

  const byType = { dine_in: 0, takeaway: 0, delivery: 0 };
  const byTypeCount = { dine_in: 0, takeaway: 0, delivery: 0 };
  orders.forEach((o) => {
    const type = o.orderType || 'takeaway';
    byType[type] = round2((byType[type] || 0) + o.grandTotal);
    byTypeCount[type] = (byTypeCount[type] || 0) + 1;
  });

  res.json({
    success: true,
    data: {
      totalSales: round2(totalSales),
      numberOfOrders: orders.length,
      averageOrderValue: orders.length ? round2(totalSales / orders.length) : 0,
      cash: round2(cash),
      upi: round2(upi),
      credit: round2(credit),
      dineInSales: byType.dine_in,
      takeawaySales: byType.takeaway,
      deliverySales: byType.delivery,
      dineInOrders: byTypeCount.dine_in,
      takeawayOrders: byTypeCount.takeaway,
      deliveryOrders: byTypeCount.delivery,
    },
  });
});

// GET /api/reports/products?from=&to=
const getProductReport = asyncHandler(async (req, res) => {
  const filter = parseRange(req.query);

  const results = await Order.aggregate([
    { $match: filter },
    { $unwind: '$items' },
    {
      $group: {
        _id: '$items.name',
        quantitySold: { $sum: '$items.quantity' },
        revenue: { $sum: '$items.total' },
      },
    },
    { $sort: { revenue: -1 } },
  ]);

  res.json({
    success: true,
    data: results.map((r) => ({ name: r._id, quantitySold: r.quantitySold, revenue: round2(r.revenue) })),
  });
});

// GET /api/reports/staff?from=&to=
const getStaffReport = asyncHandler(async (req, res) => {
  const filter = parseRange(req.query);

  const results = await Order.aggregate([
    { $match: filter },
    { $group: { _id: '$staff', sales: { $sum: '$grandTotal' }, orders: { $sum: 1 } } },
    { $sort: { sales: -1 } },
  ]);

  const staffIds = results.map((r) => r._id);
  const staffDocs = await User.find({ _id: { $in: staffIds } }).select('name role');
  const staffMap = new Map(staffDocs.map((s) => [s._id.toString(), s]));

  res.json({
    success: true,
    data: results.map((r) => ({
      staffId: r._id,
      name: staffMap.get(String(r._id))?.name || 'Unknown',
      sales: round2(r.sales),
      orders: r.orders,
    })),
  });
});

// GET /api/reports/credit
const getCreditReport = asyncHandler(async (req, res) => {
  const customersWithDue = await Customer.find({ outstandingBalance: { $gt: 0 } }).sort({ outstandingBalance: -1 });
  const totalOutstanding = customersWithDue.reduce((s, c) => s + c.outstandingBalance, 0);
  const totalCollected = await Customer.aggregate([{ $group: { _id: null, total: { $sum: '$totalPaid' } } }]);

  res.json({
    success: true,
    data: {
      totalOutstanding: round2(totalOutstanding),
      customersWithDue: customersWithDue.map((c) => ({ id: c._id, name: c.name, phone: c.phone, due: c.outstandingBalance })),
      totalPaymentsCollected: round2(totalCollected[0]?.total || 0),
    },
  });
});

// GET /api/reports/expenses?from=&to=  — combined with revenue for net amount
const getExpenseReport = asyncHandler(async (req, res) => {
  const salesFilter = parseRange(req.query);
  const expenseFilter = {};
  if (req.query.from || req.query.to) {
    expenseFilter.date = {};
    if (req.query.from) expenseFilter.date.$gte = new Date(req.query.from);
    if (req.query.to) expenseFilter.date.$lte = new Date(req.query.to);
  }

  const [orders, expenses] = await Promise.all([Order.find(salesFilter), Expense.find(expenseFilter).sort({ date: -1 })]);

  const revenue = orders.reduce((s, o) => s + o.grandTotal, 0);
  const totalExpenses = expenses.reduce((s, e) => s + e.amount, 0);

  const byCategory = {};
  expenses.forEach((e) => {
    byCategory[e.category] = round2((byCategory[e.category] || 0) + e.amount);
  });

  res.json({
    success: true,
    data: {
      revenue: round2(revenue),
      totalExpenses: round2(totalExpenses),
      netAmount: round2(revenue - totalExpenses),
      byCategory,
      expenses,
    },
  });
});

module.exports = { getSalesReport, getProductReport, getStaffReport, getCreditReport, getExpenseReport };
