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
router.use('/counters', require('./counterRoutes'));
router.use('/uploads', require('./uploadRoutes'));
router.use('/users', require('./userRoutes'));
router.use('/attendance', require('./attendanceRoutes'));
router.use('/public', require('./publicRoutes'));
router.use('/audit', require('./auditRoutes'));
router.use('/feedback', require('./feedbackRoutes'));
router.use('/kds', require('./kdsRoutes'));
router.use('/maintenance', require('./maintenanceRoutes'));
router.use('/manager', require('./managerRoutes'));
router.use('/platform', require('./platformRoutes'));
router.use('/archive', require('./archiveRoutes'));

router.get('/health', (req, res) => res.json({ success: true, message: 'PWP POS — Personalize Web Page API is running.' }));

module.exports = router;
