const {
  Order,
  PaymentTransaction,
  RefundTransaction,
  CreditTransaction,
  Expense,
  CashMovement,
  DayClose,
  InventoryTransaction,
  Feedback,
  AuditLog,
  Customer,
  Product,
  Category,
  User,
  BusinessSettings,
  DailySummary,
  ArchiveRun,
} = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { currentOutletDb, currentContext } = require('../tenancy/context');

// Keeps the (free, 512 MB) database small: every ~4 months the admin is
// reminded to download old records (a full JSON backup and an Excel-ready
// CSV of bills), then delete them from the server. A per-day summary is
// kept so sales history stays visible after the details are gone.

const ARCHIVE_EVERY_DAYS = 120;
const KEEP_RECENT_DAYS = 90;
const FREE_TIER_MB = 512;
const TZ = 'Asia/Kolkata';
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTIVE_STATUSES = ['open', 'preparing', 'ready'];

// Records archived and then deleted. Bills still being served (open tabs)
// are never touched; customers, menu, tables, settings and users stay.
const ARCHIVED = [
  { key: 'orders', Model: Order, field: 'createdAt', extra: { status: { $nin: ACTIVE_STATUSES } } },
  { key: 'payments', Model: PaymentTransaction, field: 'createdAt', extra: { status: { $nin: ['initiated', 'processing'] } } },
  { key: 'refunds', Model: RefundTransaction, field: 'createdAt' },
  { key: 'creditTransactions', Model: CreditTransaction, field: 'createdAt' },
  { key: 'expenses', Model: Expense, field: 'date' },
  { key: 'cashMovements', Model: CashMovement, field: 'createdAt' },
  { key: 'dayCloses', Model: DayClose, field: 'createdAt', extra: { status: 'closed' } },
  { key: 'inventoryTransactions', Model: InventoryTransaction, field: 'createdAt' },
  { key: 'feedback', Model: Feedback, field: 'createdAt' },
  { key: 'auditLog', Model: AuditLog, field: 'createdAt' },
];

// Included in the backup so it can be read on its own; not deleted.
const REFERENCE = [
  { key: 'customers', Model: Customer },
  { key: 'categories', Model: Category },
  { key: 'products', Model: Product, projection: { name: 1, category: 1, sellingPrice: 1, costPrice: 1, status: 1 } },
];

/** IST midnight at the start of `YYYY-MM-DD`. */
function istMidnight(dateString) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(dateString || ''))) {
    throw new ApiError(400, 'Choose a date as YYYY-MM-DD.');
  }
  const date = new Date(`${dateString}T00:00:00+05:30`);
  if (Number.isNaN(date.getTime())) throw new ApiError(400, 'Invalid date.');
  return date;
}

function istDateString(date) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(date);
}

function filterFor(entry, before) {
  return { [entry.field]: { $lt: before }, ...(entry.extra || {}) };
}

/** The cut-off for a request: given date, never inside the recent window. */
function cutoffFrom(query) {
  const before = istMidnight(query.before);
  const latest = new Date(Date.now() - KEEP_RECENT_DAYS * DAY_MS);
  if (before > latest) {
    throw new ApiError(400, `Only records older than ${KEEP_RECENT_DAYS} days can be archived. Choose ${istDateString(latest)} or earlier.`);
  }
  return before;
}

async function storageInfo() {
  try {
    const stats = await currentOutletDb().db.stats();
    const usedMB = (stats.dataSize + stats.indexSize) / 1048576;
    return { usedMB: +usedMB.toFixed(1), limitMB: FREE_TIER_MB, percent: Math.round((usedMB / FREE_TIER_MB) * 100) };
  } catch (err) {
    return null;
  }
}

// GET /api/archive/status
// Whether an archive is due (every ~4 months, or when storage runs low),
// the suggested cut-off date and how many records it would cover.
const getStatus = asyncHandler(async (req, res) => {
  const settings = await BusinessSettings.getSettings();
  const oldest = await Order.findOne({ status: { $nin: ACTIVE_STATUSES } }).sort({ createdAt: 1 }).select('createdAt').lean();
  const suggested = new Date(Date.now() - KEEP_RECENT_DAYS * DAY_MS);
  const suggestedBefore = istDateString(suggested);
  const oldOrders = await Order.countDocuments({ createdAt: { $lt: istMidnight(suggestedBefore) }, status: { $nin: ACTIVE_STATUSES } });
  const lastRun = await ArchiveRun.findOne().sort({ createdAt: -1 }).lean();
  const storage = await storageInfo();

  const since = settings.lastArchiveAt || oldest?.createdAt;
  const daysSince = since ? Math.floor((Date.now() - new Date(since).getTime()) / DAY_MS) : 0;
  const storageLow = Boolean(storage && storage.percent >= 70);
  const due = oldOrders > 0 && (daysSince >= ARCHIVE_EVERY_DAYS || storageLow);

  res.json({
    success: true,
    data: {
      due,
      storageLow,
      everyDays: ARCHIVE_EVERY_DAYS,
      keepRecentDays: KEEP_RECENT_DAYS,
      lastArchiveAt: settings.lastArchiveAt || null,
      oldestRecordAt: oldest?.createdAt || null,
      suggestedBefore,
      oldOrders,
      storage,
      lastRun: lastRun
        ? { before: istDateString(lastRun.before), status: lastRun.status, exportedAt: lastRun.exportedAt, purgedAt: lastRun.purgedAt, counts: lastRun.counts }
        : null,
    },
  });
});

function fileBase(before) {
  const ctx = currentContext();
  const name = ctx ? `${ctx.tenant.code}-${ctx.outlet.code}` : 'pos';
  return `${name}-before-${istDateString(before)}`;
}

// GET /api/archive/export?before=YYYY-MM-DD
// Full JSON backup of every record that the clean-up would delete (plus
// customers and menu for reference), streamed so large exports fit in memory.
const exportJson = asyncHandler(async (req, res) => {
  const before = cutoffFrom(req.query);
  const counts = {};
  for (const entry of ARCHIVED) counts[entry.key] = await entry.Model.countDocuments(filterFor(entry, before));

  const settings = await BusinessSettings.getSettings();
  const ctx = currentContext();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${fileBase(before)}.json"`);

  const meta = {
    format: 'pwp-pos-archive',
    version: 1,
    business: ctx ? { code: ctx.tenant.code, name: ctx.tenant.name } : null,
    outlet: ctx ? { code: ctx.outlet.code, name: ctx.outlet.name } : { name: settings.cafeName },
    before: istDateString(before),
    exportedAt: new Date().toISOString(),
    counts,
  };
  res.write(`{"meta":${JSON.stringify(meta)}`);

  const writeCollection = async (key, cursor) => {
    res.write(`,"${key}":[`);
    let first = true;
    for await (const doc of cursor) {
      if (!first) res.write(',');
      first = false;
      if (!res.write(JSON.stringify(doc))) await new Promise((resolve) => res.once('drain', resolve));
    }
    res.write(']');
  };

  for (const entry of ARCHIVED) {
    await writeCollection(entry.key, entry.Model.find(filterFor(entry, before)).sort({ [entry.field]: 1 }).lean().cursor());
  }
  for (const entry of REFERENCE) {
    await writeCollection(entry.key, entry.Model.find({}, entry.projection || {}).lean().cursor());
  }
  res.write('}');
  res.end();

  await ArchiveRun.create({ before, counts, exportedBy: req.user?._id, status: 'exported' });
});

function csvCell(value) {
  const text = value === null || value === undefined ? '' : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

// GET /api/archive/export.csv?before=YYYY-MM-DD
// One row per bill, ready to open in Excel / Google Sheets.
const exportCsv = asyncHandler(async (req, res) => {
  const before = cutoffFrom(req.query);
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${fileBase(before)}-bills.csv"`);

  const users = new Map((await User.find({}).select('name').lean()).map((u) => [String(u._id), u.name]));
  const customers = new Map((await Customer.find({}).select('name phone').lean()).map((c) => [String(c._id), c]));

  const header = [
    'Bill No', 'Date', 'Time', 'Type', 'Table/Counter', 'Customer', 'Phone', 'Items',
    'Subtotal', 'Discount', 'Tax', 'Total', 'Payment', 'Cash', 'UPI', 'Credit', 'Status', 'Staff',
  ];
  res.write(`﻿${header.join(',')}\r\n`); // BOM so Excel reads ₹ and Hindi names

  const ordersEntry = ARCHIVED[0];
  const cursor = Order.find(filterFor(ordersEntry, before)).sort({ createdAt: 1 }).lean().cursor();
  for await (const o of cursor) {
    const when = new Date(o.createdAt);
    const customer = o.customer ? customers.get(String(o.customer)) : null;
    const row = [
      o.orderNumber,
      istDateString(when),
      new Intl.DateTimeFormat('en-IN', { timeZone: TZ, hour: '2-digit', minute: '2-digit' }).format(when),
      o.orderType,
      o.tableCustomerLabel || '',
      customer?.name || o.qrCustomerContact?.name || '',
      customer?.phone || o.deliveryInfo?.phone || o.qrCustomerContact?.phone || '',
      (o.items || []).map((i) => `${i.quantity} x ${i.name}`).join('; '),
      o.subtotal, o.discount, o.tax, o.grandTotal,
      o.paymentMethod || '',
      o.paymentBreakdown?.cash || 0, o.paymentBreakdown?.upi || 0, o.paymentBreakdown?.credit || 0,
      o.status,
      o.staff ? users.get(String(o.staff)) || '' : '',
    ];
    if (!res.write(`${row.map(csvCell).join(',')}\r\n`)) await new Promise((resolve) => res.once('drain', resolve));
  }
  res.end();
});

/** Writes one DailySummary per IST day for the bills about to be deleted. */
async function summarize(before) {
  const ordersFilter = filterFor(ARCHIVED[0], before);
  const day = { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: TZ } };

  const totals = await Order.aggregate([
    { $match: ordersFilter },
    {
      $group: {
        _id: day,
        orders: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
        voidedOrders: { $sum: { $cond: [{ $eq: ['$status', 'voided'] }, 1, 0] } },
        subtotal: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$subtotal', 0] } },
        discount: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$discount', 0] } },
        tax: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$tax', 0] } },
        netSales: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$grandTotal', 0] } },
        cash: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$paymentBreakdown.cash', 0] }, 0] } },
        upi: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$paymentBreakdown.upi', 0] }, 0] } },
        card: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$paymentBreakdown.card', 0] }, 0] } },
        credit: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$paymentBreakdown.credit', 0] }, 0] } },
        dine_in: { $sum: { $cond: [{ $and: [{ $eq: ['$status', 'completed'] }, { $eq: ['$orderType', 'dine_in'] }] }, '$grandTotal', 0] } },
        takeaway: { $sum: { $cond: [{ $and: [{ $eq: ['$status', 'completed'] }, { $eq: ['$orderType', 'takeaway'] }] }, '$grandTotal', 0] } },
        delivery: { $sum: { $cond: [{ $and: [{ $eq: ['$status', 'completed'] }, { $eq: ['$orderType', 'delivery'] }] }, '$grandTotal', 0] } },
      },
    },
  ]);

  const items = await Order.aggregate([
    { $match: { ...ordersFilter, status: 'completed' } },
    { $unwind: '$items' },
    { $group: { _id: { day, name: '$items.name' }, quantity: { $sum: '$items.quantity' }, amount: { $sum: '$items.total' } } },
  ]);
  const refunds = await RefundTransaction.aggregate([
    { $match: { createdAt: { $lt: before } } },
    { $group: { _id: day, amount: { $sum: '$amount' } } },
  ]);
  const expenses = await Expense.aggregate([
    { $match: { date: { $lt: before } } },
    { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$date', timezone: TZ } }, amount: { $sum: '$amount' } } },
  ]);

  const byDay = new Map();
  const get = (date) => {
    if (!byDay.has(date)) byDay.set(date, { businessDate: date, items: [], payments: {}, byType: {} });
    return byDay.get(date);
  };
  for (const t of totals) {
    Object.assign(get(t._id), {
      orders: t.orders, voidedOrders: t.voidedOrders, subtotal: t.subtotal, discount: t.discount, tax: t.tax, netSales: t.netSales,
      payments: { cash: t.cash, upi: t.upi, card: t.card, credit: t.credit, other: 0 },
      byType: { dine_in: t.dine_in, takeaway: t.takeaway, delivery: t.delivery },
    });
  }
  for (const i of items) get(i._id.day).items.push({ name: i._id.name, quantity: i.quantity, amount: i.amount });
  for (const r of refunds) get(r._id).refunds = r.amount;
  for (const e of expenses) get(e._id).expenses = e.amount;

  for (const summary of byDay.values()) {
    summary.items.sort((a, b) => b.amount - a.amount);
    await DailySummary.updateOne({ businessDate: summary.businessDate }, { $set: summary }, { upsert: true });
  }
  return byDay.size;
}

// POST /api/archive/purge { before: 'YYYY-MM-DD' }
// Deletes the archived records -- only after their backup was downloaded.
const purge = asyncHandler(async (req, res) => {
  const before = cutoffFrom(req.body || {});
  const run = await ArchiveRun.findOne({ before, status: 'exported' }).sort({ createdAt: -1 });
  if (!run || Date.now() - run.exportedAt.getTime() > 7 * DAY_MS) {
    throw new ApiError(409, 'Download the backup for this date first, then delete.', { code: 'EXPORT_REQUIRED' });
  }

  const days = await summarize(before);
  const deleted = {};
  for (const entry of ARCHIVED) {
    const result = await entry.Model.deleteMany(filterFor(entry, before));
    deleted[entry.key] = result.deletedCount || 0;
  }

  run.status = 'purged';
  run.purgedAt = new Date();
  run.purgedBy = req.user?._id;
  run.counts = { ...run.counts, deleted, summarizedDays: days };
  await run.save();

  const settings = await BusinessSettings.getSettings();
  settings.lastArchiveAt = new Date();
  await settings.save();

  res.json({ success: true, data: { deleted, summarizedDays: days, storage: await storageInfo() } });
});

// GET /api/archive/summaries?from=YYYY-MM-DD&to=YYYY-MM-DD
// Day totals kept for archived periods.
const listSummaries = asyncHandler(async (req, res) => {
  const filter = {};
  if (req.query.from || req.query.to) {
    filter.businessDate = {};
    if (req.query.from) filter.businessDate.$gte = String(req.query.from);
    if (req.query.to) filter.businessDate.$lte = String(req.query.to);
  }
  const rows = await DailySummary.find(filter).sort({ businessDate: -1 }).limit(400).lean();
  res.json({ success: true, data: rows });
});

module.exports = { getStatus, exportJson, exportCsv, purge, listSummaries };
