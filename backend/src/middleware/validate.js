const { validationResult } = require('express-validator');
const { ApiError } = require('../utils/apiError');

// Runs after an array of express-validator checks; throws a clean 400 if any failed.
function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    const details = errors.array().map((e) => ({ field: e.path, message: e.msg }));
    throw new ApiError(400, 'Validation failed', details);
  }
  next();
}

module.exports = validate;
