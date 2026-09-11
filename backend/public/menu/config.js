// Production configuration for the Fast N Fresh customer QR menu.
//
// This static menu has no build step, so the API URL is configured here.
//
// IMPORTANT:
// - Do NOT use localhost in production.
// - Do NOT use 127.0.0.1 in production.
// - Do NOT use a private/local IP address in production.
// - The /api suffix is required because the backend API is mounted at /api
//   (see backend/src/routes/index.js and app.use('/api', routes) in app.js).
//
// This file is served by the backend itself at GET /menu (see
// app.use('/menu', express.static(...)) in backend/src/app.js), so the API
// domain below IS the same domain this page was loaded from.
//
// Verified against GET https://fast-n-fresh-slh9.onrender.com/api/health,
// which should return { "success": true, "message": "Fast N Fresh Cafe API
// is running." }.

window.FNF_CONFIG = {
  API_BASE_URL: 'https://fast-n-fresh-slh9.onrender.com/api',
  VERIFIED: true,
};
