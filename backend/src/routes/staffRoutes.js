const express = require('express');
const { listStaff, getStaffMember, createStaff, updateStaff, resetStaffPassword } = require('../controllers/staffController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

// Entire staff-management section is admin-only.
router.use(protect, authorize('admin'));

router.get('/', listStaff);
router.get('/:id', getStaffMember);
router.post('/', createStaff);
router.put('/:id', updateStaff);
router.post('/:id/reset-password', resetStaffPassword);

module.exports = router;
