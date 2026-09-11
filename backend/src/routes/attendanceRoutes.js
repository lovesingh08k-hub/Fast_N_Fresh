const express = require('express');
const { getAttendanceSummary, getStaffAttendanceDetail } = require('../controllers/attendanceController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

// Staff performance / customer-attendance analytics — admin only, per spec.
// Manager gets operational access elsewhere but NOT this analytics view.
router.use(protect, authorize('admin'));

router.get('/summary', getAttendanceSummary);
router.get('/:staffId', getStaffAttendanceDetail);

module.exports = router;
