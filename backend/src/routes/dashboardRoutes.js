const express = require('express');
const { getDashboard, getSalesOverview } = require('../controllers/dashboardController');
const { protect } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.get('/', getDashboard);
router.get('/sales-overview', getSalesOverview);

module.exports = router;
