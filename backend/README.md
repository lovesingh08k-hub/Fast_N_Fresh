# Fast N Fresh Cafe — Backend API

Node.js + Express + MongoDB REST API powering the Fast N Fresh Cafe POS app.

## Requirements

- Node.js 18+
- MongoDB 6+ running as a **replica set** (required for multi-document transactions used in
  order creation and UDHAR payments — see note below)

## 1. Local development

```bash
cd backend
npm install
Create a local `backend/.env` file and fill in the required values (JWT_SECRET, MongoDB URI, ports, and seed credentials). Never commit it.
```

### Starting MongoDB with transaction support

Order creation and credit-payment endpoints use MongoDB multi-document transactions
(`session.withTransaction`) so a bill is never half-saved — inventory, credit ledger, and
the order document all succeed or all roll back together. Transactions require MongoDB to
run as a replica set (a single-node replica set is fine for local dev):

```bash
# Start mongod with replica set support
mongod --replSet rs0 --dbpath /path/to/your/data/db

# In a separate terminal, initiate the replica set (only needed once)
mongosh --eval "rs.initiate()"
```

MongoDB Atlas clusters (M0 free tier and above) are already replica sets, so this step is
only needed for local/self-hosted MongoDB.

### Seed sample data

```bash
npm run seed
```

This creates:
- 1 admin user (`SEED_ADMIN_USERNAME` / `SEED_ADMIN_PASSWORD` from `.env`)
- 1 manager user (`SEED_MANAGER_USERNAME` / `SEED_MANAGER_PASSWORD` from `.env`)
- 1 staff user (`SEED_STAFF_USERNAME` / `SEED_STAFF_PASSWORD` from `.env`)
- 6 categories (Tea, Coffee, Snacks, Fast Food, Meals, Cold Drinks)
- 5 sample products
- 6 sample tables (Table 1–6)

### Run the server

```bash
npm run dev     # nodemon, auto-restart
# or
npm start       # plain node
```

Server starts on `http://localhost:5000` by default. Health check: `GET /api/health`.

## 2. Environment variables

Never commit `backend/.env` or any other environment file containing production secrets.

Key variables:

| Variable | Purpose |
|---|---|
| `MONGODB_URI` | MongoDB connection string |
| `JWT_SECRET` | Secret used to sign auth tokens — use a long random value in production |
| `CORS_ORIGIN` | Comma-separated allowed origins (use `*` only in development) |
| `SEED_ADMIN_*` / `SEED_STAFF_*` | Credentials used only by `npm run seed` |

## 3. Production deployment

### Option A — Render / Railway (recommended for a first deployment)

1. Push this `backend/` folder to a GitHub repo.
2. Create a new Web Service on Render or Railway, pointing at the repo/`backend` subfolder.
3. Set build command: `npm install`, start command: `npm start`.
4. Add the required environment variables directly in the Render dashboard (use a MongoDB Atlas URI
   for `MONGODB_URI` — Atlas clusters support transactions out of the box).
5. Deploy. Note the HTTPS URL Render/Railway gives you — this is your `API_BASE_URL` for
   the Flutter app.

### Option B — VPS (Ubuntu)

```bash
# On the server
sudo apt update && sudo apt install -y nodejs npm mongodb-org  # or point to Atlas instead
git clone <your-repo>
cd backend
npm install --production
Create `backend/.env` manually and fill in the real values.
npm install -g pm2
pm2 start src/app.js --name fastnfresh-api
pm2 save
pm2 startup
```

Put Nginx (or Caddy) in front for HTTPS/TLS termination and a proper domain.

### MongoDB in production

Use MongoDB Atlas (free tier is enough to start). It is a replica set by default, so
transactions work with no extra setup. Whitelist your server's IP (or `0.0.0.0/0` while
testing, then lock down), create a database user, and put the connection string in
`MONGODB_URI`.

## 4. API overview

All endpoints are prefixed with `/api`. Authenticated routes require:

```
Authorization: Bearer <JWT>
```

| Area | Base path | Notes |
|---|---|---|
| Auth | `/api/auth` | login, me, change-password, logout-all |
| Dashboard | `/api/dashboard` | today's stats, sales overview graph — admin + manager |
| Products | `/api/products` | admin manages, everyone views |
| Categories | `/api/categories` | admin manages, everyone views |
| Customers | `/api/customers` | admin+manager+staff create/edit; delete admin-only; payment (pay down UDHAR) admin+manager only |
| Orders | `/api/orders` | create (admin+manager+staff); dine-in open-tab lifecycle (items/checkout/cancel); void admin-only |
| Tables | `/api/tables` | view: everyone; manage (add/edit/deactivate): admin+manager |
| Credits (UDHAR) | `/api/credits` | `/grant` (create credit): everyone; overview/transactions/payment: admin+manager only |
| Inventory | `/api/inventory` | view for all, adjust is admin-only |
| Staff | `/api/staff` | legacy per-staff detail view, admin only |
| Users | `/api/users` | admin-only: list/create/change-role/change-status for staff & manager accounts |
| Attendance | `/api/attendance` | admin-only staff performance / customer-attendance reports |
| Uploads | `/api/uploads` | product photo upload, admin-only |
| Reports | `/api/reports` | sales/products/staff/expenses: admin-only; credit: admin+manager |
| Expenses | `/api/expenses` | admin only |
| Settings | `/api/settings` | read for all, write admin only |

Role permissions are enforced **server-side** in route middleware (`authorize('admin', 'manager')`),
not just hidden in the UI.

### Order types & Dine-In flow

Orders now carry an `orderType` (`dine_in | takeaway | delivery`). Takeaway and Delivery still use
the original one-shot `POST /api/orders` flow (server prices everything, deducts inventory, updates
credit — all in one atomic transaction). Dine-In supports **multiple simultaneous, fully separate
customer orders on the same physical table**:

```
POST   /api/tables/:tableId/orders     # start a new open (unpaid) tab for one customer
PUT    /api/orders/:id/items           # edit that tab's cart (no inventory/credit effect yet)
POST   /api/orders/:id/checkout        # bill it — same atomic pricing/inventory/credit logic as createOrder
DELETE /api/orders/:id                 # cancel an unpaid tab (customer left without ordering)
PATCH  /api/orders/:id/attendee        # handover — reassign which employee is attending (admin/manager)
```

A table's `available / occupied / reserved` status is computed live from how many open orders
reference it — never a stale stored flag. When the last open order on a table is billed or
cancelled, the table automatically shows as available again.

### Roles

`admin | manager | staff` (was `admin | staff`). See the project root README's permission matrix
for the full breakdown.

## 5. Data integrity notes

- Order totals are always recalculated on the server from the current product prices —
  the client only sends product IDs + quantities.
- Bill numbers come from an atomic MongoDB counter (`Counter` model), so they're safe
  against duplicates under concurrent requests.
- Creating an order, updating inventory, and updating a customer's UDHAR balance all
  happen inside one MongoDB transaction — either everything commits or nothing does.
- Voiding an order (admin only) reverses both the inventory and credit-ledger effects.

## 6. Product photo uploads

`POST /api/uploads/product-image` (admin only, `multipart/form-data`, field name `image`) saves the
file under `backend/uploads/products/` and returns a relative URL (e.g.
`/uploads/products/product_123.jpg`), which is stored on `Product.imageUrl` and served statically
from `GET /uploads/...`. Nothing is ever hard-coded — the Flutter app resolves the relative URL
against its configured `API_BASE_URL` at display time, so this works the same in dev and
production. 5MB upload limit; JPG/PNG/WEBP only.

In production behind a reverse proxy, make sure `/uploads` is either proxied through to this
service or served by the proxy directly from the same `backend/uploads` directory.

## 7. Fast N Fresh production environment

A production `.env` is supplied locally for this project and is intentionally ignored by git.
For Render/Railway deployment, copy those values into the service's Environment settings rather
than committing the `.env` file. Firebase Cloud Messaging additionally requires a Firebase Admin
service-account credential (`FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_PATH`)
on the backend; the Android `google-services.json` is not a substitute for that server credential.
