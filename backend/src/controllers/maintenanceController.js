const { resetOrderCounter } = require('../utils/resetOrderCounter');
const { ApiError, asyncHandler } = require('../utils/apiError');

// Temporary production maintenance endpoint. It is disabled unless an
// operator explicitly sets ORDER_COUNTER_RESET_KEY in the service environment,
// and it also requires an authenticated admin account.
const resetProductionOrderCounter = asyncHandler(async (req, res) => {
  const configuredKey = String(process.env.ORDER_COUNTER_RESET_KEY || '').trim();
  const suppliedKey = String(req.get('X-Order-Counter-Reset-Key') || '').trim();

  if (!configuredKey || suppliedKey !== configuredKey) {
    throw new ApiError(404, 'Not found.');
  }

  const archiveExisting = req.body?.archiveExisting === true;
  const result = await resetOrderCounter({ archiveExisting });

  res.json({
    success: true,
    message: result.message,
    data: {
      existingOrders: result.existingOrders,
      highestOrderNumber: result.highestOrderNumber,
      previousCounter: result.counter,
      changed: result.changed,
      archived: result.archived,
      nextOrderNumber: result.nextOrderNumber,
    },
  });
});

module.exports = { resetProductionOrderCounter };
