const { ApiError } = require('../utils/apiError');

function notFound(req, res, next) {
  next(new ApiError(404, `Route not found: ${req.method} ${req.originalUrl}`));
}

// Centralized error handler. Never leaks stack traces or internal details
// to the client in production.
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  let { statusCode, message, details } = err;

  if (err.name === 'CastError') {
    statusCode = 400;
    message = 'Invalid identifier supplied.';
  }
  if (err.code === 11000) {
    statusCode = 409;
    const field = Object.keys(err.keyPattern || {})[0] || 'field';
    message = `A record with this ${field} already exists.`;
  }
  if (err.name === 'ValidationError' && !statusCode) {
    statusCode = 400;
    message = Object.values(err.errors)
      .map((e) => e.message)
      .join(', ');
  }

  statusCode = statusCode || 500;
  message = message || 'Internal server error';

  if (statusCode === 500) {
    // Log full detail server-side only; never expose internals to the client.
    console.error('[ERROR]', err);
    message = process.env.NODE_ENV === 'production' ? 'Something went wrong.' : message;
  }

  res.status(statusCode).json({
    success: false,
    message,
    ...(details ? { details } : {}),
    ...(req.requestId ? { requestId: req.requestId } : {}),
  });
}

module.exports = { notFound, errorHandler };
