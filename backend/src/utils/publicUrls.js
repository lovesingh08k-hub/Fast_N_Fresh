// Single source of truth for building the public customer QR-menu URL.
//
// The old standalone Render Static Site (fast-n-fresh-web-menu.onrender.com)
// is disabled. The customer menu is now served directly by this backend at
// GET /menu (see app.js: app.use('/menu', express.static(...))), on the
// current production API domain.
//
// Correct:
// https://fast-n-fresh-slh9.onrender.com/menu?table=1
//
// Incorrect:
// https://fast-n-fresh-slh9.onrender.com/menu/menu?table=1
//
// Never hardcode localhost/127.0.0.1/private IPs here.
// The base URL always comes from the environment variable when set.

function publicMenuUrl(tableNumber) {
  // Prefer an explicitly configured public menu host (WEB_MENU_BASE_URL env
  // var). Ignore the old disabled Render Static Site and the backend /menu
  // host because either one can show Render's cold-start page to customers.
  // New QR codes therefore fall back to the static GitHub Pages menu.
  const configured = (process.env.WEB_MENU_BASE_URL || '').trim().replace(/\/+$/, '');
  const legacyRenderMenu = 'fast-n-fresh-web-menu.onrender.com';
  const backendMenuHost = 'fast-n-fresh-slh9.onrender.com/menu';
  const base = configured && !configured.includes(legacyRenderMenu) && !configured.includes(backendMenuHost)
    ? configured
    : 'https://lovesingh08k-hub.github.io/Fast_N_Fresh';

  const number = Number(tableNumber);

  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }

  return `${base}?table=${number}`;
}

module.exports = { publicMenuUrl };