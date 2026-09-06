# Fast N Fresh — Change Log / Verification Notes

## 2026-09-06 — Production hardening

- Backend JavaScript source passes Node syntax validation.
- Backend startup now binds the HTTP port before MongoDB is ready, allowing `/health` to return a truthful `503` during database startup.
- MongoDB connection failures no longer terminate the process immediately; the API retries the connection every 5 seconds while remaining unhealthy.
- Release Android signing remains protected: a production release still requires the owner's real `android/key.properties` and upload keystore.
- Added `npm run check` for repeatable backend syntax validation.
- The production QR menu remains `backend/public/menu` and is served at `/menu`. The `web/menu` copy is retained as the source/static-site mirror and is kept byte-for-byte aligned for the application files.

## Required before first production APK

Create the real signing files locally; do not commit them:

- `mobile/android/key.properties`
- the upload keystore (`.jks` or `.keystore`)

See `mobile/README.md` → **Release signing**.

## Runtime verification still required

The source package cannot prove physical-device behavior. Before deployment, run:

```bash
cd backend
npm ci
npm run check
npm run seed
npm start
```

and, with Flutter installed:

```bash
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --debug
flutter build apk --release
```

For the release build, use the real production keystore.

## 2026-09-06 — KOT, Receipt, QR Payment Safety, Breakfast/Biryani

- Added a KOT preview/printing path alongside the existing Kitchen Display System.
- Updated receipt PDF, Bluetooth thermal ticket, and text sharing to the requested compact cafe-bill structure, using existing BusinessSettings and Order data.
- Added `loyaltyPointsUsed` to Order with a backward-compatible default of 0.
- Removed customer-facing UTR/reference entry and the old public UTR endpoint.
- Split customer online payment attempts into `PaymentTransaction`; final Orders are created only after server-verifiable provider success.
- Added a provider abstraction and fail-closed webhook/status architecture. No PSP credentials/provider adapter are present in this repository, so customer online payment remains unavailable until a real provider is configured.
- Added an idempotent Breakfast/Biryani migration that moves existing products without changing their inventory/cost fields and creates only missing products.
- Kept `web/menu/` untouched because `backend/public/menu/` is the served `/menu` implementation.


### Printer width / paper saving
- Added a 55 mm thermal-printer option alongside 80 mm.
- Narrow receipts use a compact 30-column layout and only one feed line before cutting to reduce paper waste.
- KOT printing follows the same saved printer-width preference.
- Receipt header includes the cafe slogan and loyalty-points line remains removed.


## Production hardening — September 7, 2026
- Standardized QR menu and APK on the same Render production API.
- QR menu no longer blocks catalog rendering on payment-settings failure; GET requests retry once for Render cold starts.
- Product search is now safe, category-aware, and debounced in Flutter with stale-response protection and clear-search UX.
- Added duplicate-admin cleanup command and defensive admin-list deduplication.
- Product uploads are persisted in MongoDB so new product thumbnails survive Render restarts/redeploys; legacy disk URLs remain supported.
