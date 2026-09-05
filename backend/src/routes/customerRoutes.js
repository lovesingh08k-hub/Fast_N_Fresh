const express = require('express');
const {
  listCustomers,
  getCustomer,
  createCustomer,
  updateCustomer,
  deleteCustomer,
  recordPayment,
} = require('../controllers/customerController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

router.use(protect);

router.get('/', listCustomers); // admin + staff
router.get('/:id', getCustomer);
router.post('/', createCustomer); // admin + staff can add customers
router.put('/:id', updateCustomer); // admin + staff can edit
router.delete('/:id', authorize('admin'), deleteCustomer); // staff cannot delete customers
router.post('/:id/payment', authorize('admin', 'manager'), recordPayment); // paying down UDHAR = managing an existing credit record

module.exports = router;
