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

## 1.1.0+5 — Shopto-inspired UX redesign
- Smooth tab transitions and Material 3 NavigationBar.
- Direct dark/light toggle from POS and Orders.
- 480ms app-wide theme transition.
- Route fade/slide transitions.
- More compact POS context header and subtle product/cart motion.
- Corrected light/dark ThemeData palette isolation.

## Shopto-style operational flow pass — 2026-09-10
- Added separate kitchen lifecycle (`new/preparing/ready/served`) to the order model.
- Added real multi-KOT history with duplicate-quantity protection.
- Added KDS support for dine-in, takeaway, delivery and QR orders.
- Added Dashboard/More quick access to New Sale, Kitchen and Tables.
- Added per-KOT Bluetooth/system printing.

## POS blank body hardening — v1.5.23
- Fixed the initial loading-state layout crash caused by a non-shrink-wrapped skeleton GridView inside a scrollable Column/ListView.
- Simplified POS to a single scroll viewport so mode/search/catalog remain visible during backend cold starts and catalog failures.
- Added explicit POS-body fallback/retry state.
