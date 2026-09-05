const { AuditLog } = require('../models');
const { asyncHandler } = require('../utils/apiError');

const listAuditLogs = asyncHandler(async (req, res) => {
  const { action, entityType, from, to } = req.query;
  const filter = {};
  if (action) filter.action = action;
  if (entityType) filter.entityType = entityType;
  if (from || to) filter.createdAt = {};
  if (from) filter.createdAt.$gte = new Date(from);
  if (to) filter.createdAt.$lte = new Date(to);
  const logs = await AuditLog.find(filter)
    .populate('actor', 'name role username')
    .sort({ createdAt: -1 })
    .limit(300);
  res.json({ success: true, data: logs });
});

module.exports = { listAuditLogs };
