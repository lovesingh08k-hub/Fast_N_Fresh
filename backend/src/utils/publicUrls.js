// Single source of truth for building the public customer QR-menu URL.
//
// The old standalone Render Static Site (fast-n-fresh-web-menu.onrender.com)
// is disabled. The customer menu is now served directly by this backend at
// GET /menu (see app.js: app.use('/menu', express.static(...))), on the
// current production API domain.
//
// Correct:
// https://fast-n-fresh-api.onrender.com/menu?table=1
//
// Incorrect:
// https://fast-n-fresh-api.onrender.com/menu/menu?table=1
//
// Never hardcode localhost/127.0.0.1/private IPs here.
// The base URL always comes from the environment variable when set.

function publicMenuUrl(tableNumber) {
  // Prefer an explicitly configured public menu host (WEB_MENU_BASE_URL env
  // var), but fall back to the current production backend. The backend
  // serves /menu itself, so QR ordering does not depend on a second Render
  // Static Site being deployed.
  const base = (process.env.WEB_MENU_BASE_URL || 'https://fast-n-fresh-api.onrender.com/menu')
    .trim()
    .replace(/\/+$/, '');

  const number = Number(tableNumber);

  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }

  return `${base}?table=${number}`;
}

module.exports = { publicMenuUrl };