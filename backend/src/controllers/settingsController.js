const { BusinessSettings } = require('../models');
const { asyncHandler } = require('../utils/apiError');

const getSettings = asyncHandler(async (req, res) => {
  const settings = await BusinessSettings.getSettings();
  res.json({ success: true, data: settings });
});

const updateSettings = asyncHandler(async (req, res) => {
  const settings = await BusinessSettings.getSettings();

  const editable = [
    'cafeName',
    'tagline',
    'phone',
    'address',
    'gstNumber',
    'logoUrl',
    'upiId',
    'receiptFooter',
    'taxEnabled',
    'taxPercent',
    'defaultDiscount',
    'currencySymbol',
    'primaryColor',
  ];
  editable.forEach((field) => {
    if (req.body[field] !== undefined) settings[field] = req.body[field];
  });

  await settings.save();
  res.json({ success: true, data: settings });
});

module.exports = { getSettings, updateSettings };
