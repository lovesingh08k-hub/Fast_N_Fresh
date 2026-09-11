const { User, Order } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/staff
const listStaff = asyncHandler(async (req, res) => {
  const staff = await User.find({ role: 'staff' }).sort({ name: 1 });
  res.json({ success: true, data: staff.map((s) => s.toSafeJSON()) });
});

// GET /api/staff/:id — includes today's performance
const getStaffMember = asyncHandler(async (req, res) => {
  const staff = await User.findOne({ _id: req.params.id, role: 'staff' });
  if (!staff) throw new ApiError(404, 'Staff member not found.');

  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const todaysOrders = await Order.find({
    staff: staff._id,
    createdAt: { $gte: startOfToday },
    status: 'completed',
  });

  const todaysSales = todaysOrders.reduce((sum, o) => sum + o.grandTotal, 0);

  res.json({
    success: true,
    data: {
      staff: staff.toSafeJSON(),
      today: {
        sales: Math.round(todaysSales * 100) / 100,
        bills: todaysOrders.length,
      },
    },
  });
});

// POST /api/staff
const createStaff = asyncHandler(async (req, res) => {
  const { name, phone, username, password } = req.body;

  if (!name || !phone || !username || !password) {
    throw new ApiError(400, 'Name, phone, username and password are all required.');
  }
  if (password.length < 6) {
    throw new ApiError(400, 'Password must be at least 6 characters.');
  }

  const existing = await User.findOne({ username: username.toLowerCase().trim() });
  if (existing) throw new ApiError(409, 'This username is already taken.');

  const user = new User({
    name: name.trim(),
    phone: phone.trim(),
    username: username.toLowerCase().trim(),
    role: 'staff',
  });
  await user.setPassword(password);
  await user.save();

  res.status(201).json({ success: true, data: user.toSafeJSON() });
});

// PUT /api/staff/:id
const updateStaff = asyncHandler(async (req, res) => {
  const staff = await User.findOne({ _id: req.params.id, role: 'staff' });
  if (!staff) throw new ApiError(404, 'Staff member not found.');

  const { name, phone, status } = req.body;
  if (name !== undefined) staff.name = name.trim();
  if (phone !== undefined) staff.phone = phone.trim();
  if (status !== undefined) staff.status = status;

  await staff.save();
  res.json({ success: true, data: staff.toSafeJSON() });
});

// POST /api/staff/:id/reset-password  { newPassword }
const resetStaffPassword = asyncHandler(async (req, res) => {
  const { newPassword } = req.body;
  if (!newPassword || newPassword.length < 6) {
    throw new ApiError(400, 'New password must be at least 6 characters.');
  }

  const staff = await User.findOne({ _id: req.params.id, role: 'staff' });
  if (!staff) throw new ApiError(404, 'Staff member not found.');

  await staff.setPassword(newPassword);
  staff.tokenVersion += 1; // force re-login on all devices
  await staff.save();

  res.json({ success: true, message: 'Password reset successfully.' });
});

module.exports = { listStaff, getStaffMember, createStaff, updateStaff, resetStaffPassword };
