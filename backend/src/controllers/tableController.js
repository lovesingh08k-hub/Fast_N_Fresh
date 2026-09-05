const QRCode = require('qrcode');
const { Table, Order } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { publicMenuUrl } = require('../utils/publicUrls');

// Best-effort: pull a number out of a table name like "Table 5" -> 5. Used
// only as a convenience default when creating a table; never overwrites an
// explicitly-provided number and silently skips if that number is taken or
// no digits are found (admin can always set/fix it later via updateTable).
async function deriveNumberFromName(name) {
  const match = String(name).match(/(\d+)/);
  if (!match) return undefined;
  const candidate = Number(match[1]);
  const taken = await Table.findOne({ number: candidate });
  return taken ? undefined : candidate;
}

// GET /api/tables — list with a computed liveStatus + open order count so the
// UI never has to guess; `status` itself may lag (e.g. 'reserved') by design.
const listTables = asyncHandler(async (req, res) => {
  const tables = await Table.find({ active: true }).sort({ name: 1 });

  const openCounts = await Order.aggregate([
    { $match: { status: 'open', table: { $ne: null } } },
    { $group: { _id: '$table', count: { $sum: 1 } } },
  ]);
  const countMap = new Map(openCounts.map((c) => [c._id.toString(), c.count]));

  const data = tables.map((t) => {
    const openOrderCount = countMap.get(t._id.toString()) || 0;
    return {
      ...t.toObject(),
      openOrderCount,
      liveStatus: openOrderCount > 0 ? 'occupied' : t.status === 'reserved' ? 'reserved' : 'available',
    };
  });

  res.json({ success: true, data });
});

// GET /api/tables/:id — table + all its currently open (unpaid) orders.
const getTable = asyncHandler(async (req, res) => {
  const table = await Table.findOne({ _id: req.params.id, active: true });
  if (!table) throw new ApiError(404, 'Table not found.');

  const openOrders = await Order.find({ table: table._id, status: 'open' })
    .populate('staff', 'name')
    .populate('customer', 'name phone')
    .sort({ createdAt: 1 });

  res.json({ success: true, data: { table, openOrders } });
});

const createTable = asyncHandler(async (req, res) => {
  const { name, capacity, number } = req.body;
  if (!name || !name.trim()) throw new ApiError(400, 'Table name/number is required.');

  let qrNumber = number;
  if (qrNumber !== undefined && qrNumber !== null && qrNumber !== '') {
    const exists = await Table.findOne({ number: qrNumber });
    if (exists) throw new ApiError(409, `Table number ${qrNumber} is already in use.`);
  } else {
    qrNumber = await deriveNumberFromName(name);
  }

  const table = await Table.create({ name: name.trim(), capacity: capacity || 4, number: qrNumber || undefined });
  res.status(201).json({ success: true, data: table });
});

const updateTable = asyncHandler(async (req, res) => {
  const table = await Table.findOne({ _id: req.params.id, active: true });
  if (!table) throw new ApiError(404, 'Table not found.');

  const { name, capacity, status, number } = req.body;
  if (name !== undefined) table.name = name.trim();
  if (capacity !== undefined) table.capacity = capacity;
  if (number !== undefined) {
    if (number === null || number === '') {
      table.number = undefined;
    } else {
      const numValue = Number(number);
      if (!Number.isInteger(numValue) || numValue < 1) {
        throw new ApiError(400, 'Table number must be a positive whole number.');
      }
      const clash = await Table.findOne({ number: numValue, _id: { $ne: table._id } });
      if (clash) throw new ApiError(409, `Table number ${numValue} is already used by "${clash.name}".`);
      table.number = numValue;
    }
  }
  if (status !== undefined) {
    if (!['available', 'occupied', 'reserved'].includes(status)) {
      throw new ApiError(400, 'Invalid status.');
    }
    // Manually marking "occupied" isn't meaningful — that's derived from open
    // orders — but 'reserved' and manually resetting to 'available' are.
    if (status === 'occupied') throw new ApiError(400, "Table status becomes 'occupied' automatically once an order is opened on it.");
    table.status = status;
  }

  await table.save();
  res.json({ success: true, data: table });
});

// Deactivate (never hard-delete — preserves historical order/report data).
const deleteTable = asyncHandler(async (req, res) => {
  const table = await Table.findById(req.params.id);
  if (!table) throw new ApiError(404, 'Table not found.');

  const hasOpenOrders = await Order.exists({ table: table._id, status: 'open' });
  if (hasOpenOrders) {
    throw new ApiError(409, 'Cannot deactivate a table with active (unpaid) orders on it.');
  }

  table.active = false;
  await table.save();
  res.json({ success: true, message: 'Table deactivated.' });
});

// GET /api/tables/:id/qr — returns a PNG QR code encoding this table's
// public ordering URL (https://PUBLIC_FRONTEND_URL/menu?table=N). Admin
// panel uses this to display/download/print per-table QR codes. Protected
// like the rest of table management — QR *images* aren't sensitive, but
// this keeps the surface consistent and avoids an unauthenticated endpoint
// that enumerates every table.
const getTableQr = asyncHandler(async (req, res) => {
  const table = await Table.findOne({ _id: req.params.id, active: true });
  if (!table) throw new ApiError(404, 'Table not found.');
  if (!table.number) {
    throw new ApiError(400, 'This table has no QR number assigned yet. Set one first via Edit Table.');
  }

  let url;
  try {
    url = publicMenuUrl(table.number);
  } catch (err) {
    throw new ApiError(500, err.message);
  }

  const png = await QRCode.toBuffer(url, { type: 'png', width: 512, margin: 2 });
  res.set('Content-Type', 'image/png');
  res.set('Content-Disposition', `inline; filename="table-${table.number}-qr.png"`);
  res.send(png);
});

module.exports = { listTables, getTable, createTable, updateTable, deleteTable, getTableQr };
