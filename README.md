# Fast N Fresh Cafe — Cafe Management & POS System

A complete production-oriented cafe management application:

- **`backend/`** — Node.js + Express + MongoDB REST API (auth, POS billing,
  UDHAR/credit ledger, inventory, staff, reports, expenses)
- **`mobile/`** — Flutter Android app (POS billing, dashboard, customers,
  products, inventory, staff, reports, receipts)

## Quick start

```bash
# 1. Backend
cd backend
npm install
Create `backend/.env` locally with your MongoDB, JWT, and seed credentials (never commit it).
mongod --replSet rs0 --dbpath /path/to/data/db   # separate terminal; see backend/README.md
mongosh --eval "rs.initiate()"                   # one-time
npm run seed                  # creates admin/staff/categories/sample products
npm run dev                   # starts the API on http://localhost:5000

# 2. Mobile app (separate terminal)
cd mobile
flutter pub get
flutter run                   # defaults to http://10.0.2.2:5000/api (Android emulator)
```

Log in with the admin, manager, or staff credentials from your `backend/.env`
(`SEED_ADMIN_USERNAME` / `SEED_ADMIN_PASSWORD`, `SEED_MANAGER_USERNAME` /
`SEED_MANAGER_PASSWORD`, `SEED_STAFF_USERNAME` / `SEED_STAFF_PASSWORD`).

## Full documentation

- Backend setup, environment variables, MongoDB transactions, API reference,
  and production deployment: **[`backend/README.md`](backend/README.md)**
- Mobile build/run instructions, API URL configuration for
  emulator/device/production, APK build & signing, project structure:
  **[`mobile/README.md`](mobile/README.md)**
- Order types (Dine-In/Takeaway/Delivery), table management, multi-customer
  tables, the Admin/Manager/Staff role system, staff attendance tracking,
  and product photos — files changed, DB changes, new endpoints, full
  permission matrix, and a scenario-by-scenario testing trace:
  **[`CHANGES.md`](CHANGES.md)**

## What's implemented

- JWT authentication with role-based authorization enforced server-side
  (Admin / Manager / Staff), not just hidden in the UI
- Order types — Dine-In, Takeaway, Delivery — with table management and
  genuinely separate, simultaneous customer orders on the same table (each
  with its own cart, bill, payment, and receipt)
- POS billing: cart, discounts, CASH / UPI / CREDIT payment, server-side price
  and total calculation, atomic order creation (MongoDB transactions) covering
  inventory deduction and UDHAR ledger updates together
- UDHAR / credit management: staff can give credit, but only Manager/Admin can
  view credit history and outstanding balances — enforced on both the API and
  the UI; per-customer ledger, record payments, outstanding balance tracking
- Automatic staff-attendance tracking — whichever employee is logged in when
  an order starts is recorded as the attendee, with an Admin-only staff
  performance report
- Product, category, and inventory management with low-stock alerts, a full
  stock-adjustment audit trail, and product photo upload
- Staff/Manager management (admin-only): create accounts, change roles,
  activate/deactivate, view per-staff sales performance
- Admin dashboard: today's stats, sales overview graph (today/yesterday/
  week/month), recent orders, top-selling products
- Reports: sales (with order-type breakdown), products, staff, credit, and
  expenses (revenue − expenses = net)
- PDF receipts (58mm/80mm) showing order type/table, with print and share
  (WhatsApp/etc.) support
- Loading/empty/error states throughout, offline banner, sequential/safe bill
  numbering, void/reversal flow for completed orders

## Notes on this delivery

MongoDB and the Flutter SDK were not available in the environment this project
was generated in, so the backend's module graph was verified to load
correctly (no syntax/import errors) but not run against a live database, and
the Flutter app could not be compiled to an APK here. Both READMEs give the
exact commands to install dependencies, run, and build on your own machine —
please run through them once end-to-end and open an issue/note anything that
needs adjusting for your local setup.
