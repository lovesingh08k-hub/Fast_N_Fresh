const rateLimit = require('express-rate-limit');

const loginLimiter = rateLimit({
  windowMs: (Number(process.env.LOGIN_RATE_LIMIT_WINDOW_MIN) || 15) * 60 * 1000,
  max: Number(process.env.LOGIN_RATE_LIMIT_MAX) || 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many login attempts. Please try again later.',
  },
});

// Public menu is read-only but hit by every customer's phone on every page
// load/refresh — generous but bounded.
const publicMenuLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: Number(process.env.PUBLIC_MENU_RATE_LIMIT_MAX) || 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests. Please try again shortly.' },
});

// Placing an order writes to the DB, so keep this tighter per IP to blunt
// scripted abuse while still allowing a genuine customer to retry a failed
// order a few times.
const publicOrderLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: Number(process.env.PUBLIC_ORDER_RATE_LIMIT_MAX) || 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many orders placed from this device. Please wait a few minutes and try again.' },
});

const publicFeedbackLimiter = rateLimit({ windowMs: 10 * 60 * 1000, max: 10, standardHeaders: true, legacyHeaders: false, message: { success: false, message: 'Too many feedback attempts. Please try again later.' } });

module.exports = { loginLimiter, publicMenuLimiter, publicOrderLimiter, publicFeedbackLimiter };
