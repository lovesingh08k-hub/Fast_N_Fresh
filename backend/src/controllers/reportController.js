const { Order, Customer, Expense, User, RefundTransaction } = require('../models');
const { asyncHandler } = require('../utils/apiError');
const { parseClientDate } = require('../utils/dateRanges');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function parseRange(query) {
  const filter = { status: 'completed', preLaunchTestData: { $ne: true } };
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) filter.createdAt.$gte = parseClientDate(query.from);
    if (query.to) filter.createdAt.$lte = parseClientDate(query.to);
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
  const card = orders.reduce((s, o) => s + (o.paymentBreakdown?.card || 0), 0);
  const online = orders.reduce((s, o) => s + (o.paymentBreakdown?.online || 0), 0);
  const discount = orders.reduce((s, o) => s + (o.discount || 0), 0);
  const tax = orders.reduce((s, o) => s + (o.tax || 0), 0);
  const serviceCharge = orders.reduce((s, o) => s + (o.serviceCharge || 0), 0);
  const complimentary = orders.filter((o) => o.complimentary || o.paymentMethod === 'COMPLIMENTARY');

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
      card: round2(card),
      online: round2(online),
      discount: round2(discount),
      tax: round2(tax),
      serviceCharge: round2(serviceCharge),
      complimentaryOrders: complimentary.length,
      complimentaryValue: round2(complimentary.reduce((s, o) => s + (o.subtotal || 0), 0)),
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
    if (req.query.from) expenseFilter.date.$gte = parseClientDate(req.query.from);
    if (req.query.to) expenseFilter.date.$lte = parseClientDate(req.query.to);
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

// GET /api/reports/tax?from=&to=
// GST summary for filing: taxable value and CGST/SGST/IGST per rate.
const getTaxReport = asyncHandler(async (req, res) => {
  const filter = parseRange(req.query);
  const [rates, totals] = await Promise.all([
    Order.aggregate([
      { $match: filter },
      { $unwind: '$taxes' },
      {
        $group: {
          _id: '$taxes.rate',
          taxable: { $sum: '$taxes.taxable' },
          cgst: { $sum: '$taxes.cgst' },
          sgst: { $sum: '$taxes.sgst' },
          igst: { $sum: '$taxes.igst' },
          tax: { $sum: '$taxes.tax' },
        },
      },
      { $sort: { _id: 1 } },
    ]),
    Order.aggregate([
      { $match: filter },
      {
        $group: {
          _id: null,
          bills: { $sum: 1 },
          subtotal: { $sum: '$subtotal' },
          discount: { $sum: '$discount' },
          serviceCharge: { $sum: '$serviceCharge' },
          packagingCharge: { $sum: '$packagingCharge' },
          deliveryCharge: { $sum: '$deliveryCharge' },
          tax: { $sum: '$tax' },
          roundOff: { $sum: '$roundOff' },
          netSales: { $sum: '$grandTotal' },
          firstInvoice: { $min: '$invoiceNumber' },
          lastInvoice: { $max: '$invoiceNumber' },
        },
      },
    ]),
  ]);
  const t = totals[0] || {};
  res.json({
    success: true,
    data: {
      rates: rates.map((r) => ({
        rate: r._id, taxable: round2(r.taxable), cgst: round2(r.cgst), sgst: round2(r.sgst), igst: round2(r.igst), tax: round2(r.tax),
      })),
      bills: t.bills || 0,
      subtotal: round2(t.subtotal || 0),
      discount: round2(t.discount || 0),
      serviceCharge: round2(t.serviceCharge || 0),
      packagingCharge: round2(t.packagingCharge || 0),
      deliveryCharge: round2(t.deliveryCharge || 0),
      tax: round2(t.tax || 0),
      roundOff: round2(t.roundOff || 0),
      netSales: round2(t.netSales || 0),
      firstInvoice: t.firstInvoice || null,
      lastInvoice: t.lastInvoice || null,
    },
  });
});

// GET /api/reports/day-end?date=YYYY-MM-DD
// Day-end (Z) report: everything a cashier closes the day with.
const getDayEndReport = asyncHandler(async (req, res) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.date || ''))
    ? String(req.query.date)
    : new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
  const start = new Date(`${date}T00:00:00+05:30`);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  const range = { $gte: start, $lt: end };

  const [all, expenses, refunds] = await Promise.all([
    Order.find({ createdAt: range, preLaunchTestData: { $ne: true } }).lean(),
    Expense.find({ date: range }).lean(),
    RefundTransaction.find({ processedAt: range }).lean(),
  ]);
  const done = all.filter((o) => o.status === 'completed');
  const sum = (list, pick) => round2(list.reduce((s, o) => s + (Number(pick(o)) || 0), 0));

  const taxByRate = new Map();
  for (const o of done) {
    for (const t of o.taxes || []) {
      const row = taxByRate.get(t.rate) || { rate: t.rate, taxable: 0, cgst: 0, sgst: 0, igst: 0, tax: 0 };
      for (const k of ['taxable', 'cgst', 'sgst', 'igst', 'tax']) row[k] = round2(row[k] + (t[k] || 0));
      taxByRate.set(t.rate, row);
    }
  }
  const items = new Map();
  for (const o of done) {
    for (const i of o.items || []) {
      const row = items.get(i.name) || { name: i.name, quantity: 0, amount: 0 };
      row.quantity += i.quantity;
      row.amount = round2(row.amount + (i.total || 0));
      items.set(i.name, row);
    }
  }
  const invoices = done.map((o) => o.invoiceNumber).filter(Boolean).sort();

  res.json({
    success: true,
    data: {
      date,
      bills: done.length,
      cancelled: all.filter((o) => o.status === 'voided').length,
      openBills: all.filter((o) => ['open', 'preparing', 'ready'].includes(o.status)).length,
      firstInvoice: invoices[0] || null,
      lastInvoice: invoices[invoices.length - 1] || null,
      subtotal: sum(done, (o) => o.subtotal),
      discount: sum(done, (o) => o.discount),
      serviceCharge: sum(done, (o) => o.serviceCharge),
      packagingCharge: sum(done, (o) => o.packagingCharge),
      deliveryCharge: sum(done, (o) => o.deliveryCharge),
      tax: sum(done, (o) => o.tax),
      roundOff: sum(done, (o) => o.roundOff),
      netSales: sum(done, (o) => o.grandTotal),
      taxes: [...taxByRate.values()].sort((a, b) => a.rate - b.rate),
      payments: {
        cash: sum(done, (o) => o.paymentBreakdown?.cash),
        upi: sum(done, (o) => o.paymentBreakdown?.upi),
        card: sum(done, (o) => o.paymentBreakdown?.card),
        online: sum(done, (o) => o.paymentBreakdown?.online),
        credit: sum(done, (o) => o.paymentBreakdown?.credit),
      },
      byType: {
        dine_in: sum(done.filter((o) => o.orderType === 'dine_in'), (o) => o.grandTotal),
        takeaway: sum(done.filter((o) => o.orderType === 'takeaway'), (o) => o.grandTotal),
        delivery: sum(done.filter((o) => o.orderType === 'delivery'), (o) => o.grandTotal),
      },
      complimentary: {
        bills: done.filter((o) => o.complimentary).length,
        value: sum(done.filter((o) => o.complimentary), (o) => o.subtotal),
      },
      refunds: sum(refunds, (r) => r.amount),
      expenses: sum(expenses, (e) => e.amount),
      cashExpenses: sum(expenses.filter((e) => e.paymentMethod === 'CASH'), (e) => e.amount),
      topItems: [...items.values()].sort((a, b) => b.amount - a.amount).slice(0, 15),
    },
  });
});

module.exports = { getSalesReport, getProductReport, getStaffReport, getCreditReport, getExpenseReport, getTaxReport, getDayEndReport };
