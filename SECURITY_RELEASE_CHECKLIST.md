# Production release checklist

- Set `NODE_ENV=production`.
- Set a strong random `JWT_SECRET` (32+ chars; never commit it).
- Set `MONGO_URI` to the production MongoDB database with least-privilege credentials.
- Set `CORS_ORIGIN` to the exact deployed menu/admin origins (comma-separated).
- Configure Firebase Admin credentials only through the hosting secret manager if push notifications are enabled.
- Keep `mobile/android/key.properties` and the upload keystore outside source control. Copy `key.properties.example` locally and use the existing production keystore for updates.
- Verify `/health` returns HTTP 200 only when MongoDB is connected.
- Run Flutter `pub get`, `analyze`, `test`, and `build apk --release` on the release machine.
- Test QR Cash, QR UPI cancel/back, QR UPI successful payment + UTR, Kitchen NEW→PREPARING→READY, checkout, duplicate submit, and offline/reconnect.
