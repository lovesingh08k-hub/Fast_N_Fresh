# Fast N Fresh — UI / Dashboard Fixes

## v1.1.0+3

- Added persistent app-wide Light / Dark mode in Settings.
- Reworked the palette to a restrained, professional POS style.
- Removed red from normal payment/history presentation; CREDIT now uses a muted accent.
- Reserved danger red for destructive/error states.
- Fixed Dashboard → Recent Orders status presentation:
  - `open` → NEW
  - `preparing` → PREPARING
  - `ready` → READY
  - `completed` → COMPLETED
  - `voided` → VOIDED
- Completed orders can no longer render the QR `NEW / PENDING` badge.
- QR pending presentation now uses subtle amber instead of red.
- Normalized status/payment values from API responses for resilient UI mapping.
- Improved Recent Orders spacing and overflow handling on small screens.
- Backend dashboard response now preserves the real order lifecycle status.
