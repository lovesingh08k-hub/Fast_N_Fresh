const express = require('express');
const { getCreditOverview, getRecentTransactions, recordCreditPayment, grantCredit } = require('../controllers/creditController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

// Staff can GIVE credit but must never see history/outstanding totals —
// enforced here at the API layer, not just hidden in the Flutter UI.
router.get('/', authorize('admin', 'manager'), getCreditOverview);
router.get('/transactions', authorize('admin', 'manager'), getRecentTransactions);

// Creating a new credit transaction (the "staff can give credit" requirement).
router.post('/grant', grantCredit);

// Paying down an existing balance counts as "managing" an existing credit
// record, which per the permission matrix is manager/admin only.
router.post('/payment', authorize('admin', 'manager'), recordCreditPayment);

module.exports = router;
