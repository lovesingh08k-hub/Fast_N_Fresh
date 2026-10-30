const express = require('express');
const c = require('../controllers/archiveController');
const { protect, authorize } = require('../middleware/auth');

// Export-then-delete of old records, admin only (per outlet).
const router = express.Router();

router.use(protect, authorize('admin'));
router.get('/status', c.getStatus);
router.get('/export', c.exportJson);
router.get('/export.csv', c.exportCsv);
router.post('/purge', c.purge);
router.get('/summaries', c.listSummaries);

module.exports = router;
