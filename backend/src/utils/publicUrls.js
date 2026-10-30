// Single source of truth for building the public customer QR-menu URL.
//
// The base URL comes from the WEB_MENU_BASE_URL env var (e.g. the GitHub
// Pages site that hosts web/menu). If it is not set, fall back to this
// backend's own /menu route on Render (RENDER_EXTERNAL_URL is set
// automatically by Render).
//
// Correct:
// https://your-backend.onrender.com/menu?table=1
//
// Incorrect:
// https://your-backend.onrender.com/menu/menu?table=1
//
// Never hardcode localhost/127.0.0.1/private IPs here.

// `outletKey` ("<businessCode>:<outletCode>") sends the customer to one
// outlet of a platform client; without it the default client is used.
function publicMenuUrl(tableNumber, outletKey = '') {
  const configured = (process.env.WEB_MENU_BASE_URL || '').trim().replace(/\/+$/, '');
  const renderUrl = (process.env.RENDER_EXTERNAL_URL || '').trim().replace(/\/+$/, '');
  const base = configured || (renderUrl ? `${renderUrl}/menu` : '');

  if (!base) {
    throw new Error('WEB_MENU_BASE_URL is not set in environment variables.');
  }

  const number = Number(tableNumber);

  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }

  const outlet = outletKey ? `&o=${encodeURIComponent(outletKey)}` : '';
  return `${base}?table=${number}${outlet}`;
}

module.exports = { publicMenuUrl };
