const express = require('express');
const { protect, authorize } = require('../middleware/auth');
const { listAuditLogs } = require('../controllers/auditController');
const router = express.Router();
router.use(protect, authorize('admin', 'manager'));
router.get('/', listAuditLogs);
module.exports = router;
