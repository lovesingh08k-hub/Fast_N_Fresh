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
