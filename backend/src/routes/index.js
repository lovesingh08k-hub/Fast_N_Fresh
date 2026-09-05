const express = require('express');

const router = express.Router();

router.use('/auth', require('./authRoutes'));
router.use('/dashboard', require('./dashboardRoutes'));
router.use('/products', require('./productRoutes'));
router.use('/categories', require('./categoryRoutes'));
router.use('/customers', require('./customerRoutes'));
router.use('/orders', require('./orderRoutes'));
router.use('/credits', require('./creditRoutes'));
router.use('/inventory', require('./inventoryRoutes'));
router.use('/staff', require('./staffRoutes'));
router.use('/reports', require('./reportRoutes'));
router.use('/expenses', require('./expenseRoutes'));
router.use('/settings', require('./settingsRoutes'));
router.use('/tables', require('./tableRoutes'));
router.use('/uploads', require('./uploadRoutes'));
router.use('/users', require('./userRoutes'));
router.use('/attendance', require('./attendanceRoutes'));
router.use('/public', require('./publicRoutes'));
router.use('/audit', require('./auditRoutes'));
router.use('/feedback', require('./feedbackRoutes'));
router.use('/kds', require('./kdsRoutes'));

router.get('/health', (req, res) => res.json({ success: true, message: 'Fast N Fresh Cafe API is running.' }));

module.exports = router;
