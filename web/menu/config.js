// Production configuration for the Fast N Fresh customer QR menu.
//
// This static menu is deployed to GitHub Pages, so QR customers do not hit
// the Render backend just to load the HTML and wait for a cold start.
// The menu then calls the production API below.
//
// IMPORTANT:
// - Do NOT use localhost in production.
// - Do NOT use 127.0.0.1 in production.
// - Do NOT use a private/local IP address in production.
// - The /api suffix is required because the backend API is mounted at /api.
//
// API URL has been verified against the production backend health endpoint
// (GET https://fast-n-fresh-slh9.onrender.com/api/health).
//
// This folder is the production static customer menu deployed by GitHub
// Pages. The backend still contains a /menu copy for backward compatibility.

window.FNF_CONFIG = {
  API_BASE_URL: 'https://fast-n-fresh-slh9.onrender.com/api',
  VERIFIED: true,
};
