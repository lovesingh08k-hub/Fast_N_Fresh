// Production configuration for the Fast N Fresh customer QR menu.
//
// This static menu has no build step, so the API URL is configured here.
//
// IMPORTANT:
// - Do NOT use localhost in production.
// - Do NOT use 127.0.0.1 in production.
// - Do NOT use a private/local IP address in production.
// - The /api suffix is required because the backend API is mounted at /api.
//
// API URL has been verified against the production backend health endpoint
// (GET https://fast-n-fresh-api.onrender.com/api/health).
//
// NOTE: This copy of the customer menu (web/menu) is NOT what production
// customers currently see. The live QR menu is served by the backend at
// GET /menu from backend/public/menu (see app.js). This folder was the
// source for the old, now-disabled fast-n-fresh-web-menu.onrender.com
// Render Static Site. Kept in sync here to avoid a second stale URL if it
// is ever redeployed.

window.FNF_CONFIG = {
  API_BASE_URL: 'https://fast-n-fresh-api.onrender.com/api',
  VERIFIED: true,
};
