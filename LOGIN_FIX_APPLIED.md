# Login production fix applied

## What was fixed

1. **Production API URL is now a safe built-in default**
   - `mobile/lib/core/network/api_config.dart` defaults to:
     `https://fast-n-fresh-slh9.onrender.com/api`
   - `--dart-define=API_BASE_URL=...` still overrides it for other environments.

2. **Login now retries transient Render cold-start failures**
   - `mobile/lib/services/auth_service.dart` retries connection/timeout/5xx failures up to two additional times.
   - 400/401/403 credential/account errors are never retried.
   - Login response is validated before parsing, preventing a malformed server response from becoming an unexplained generic failure.

3. **Longer network timeouts**
   - connect: 20s
   - send: 20s
   - receive: 45s
   This accommodates a sleeping Render service waking up.

4. **DB-aware backend health endpoint**
   - Added `GET /health` to `backend/src/app.js`.
   - Returns HTTP 200 only when MongoDB is connected; otherwise 503.

## Important deployment step

The mobile changes must be rebuilt into a new APK. The backend change must be deployed to Render if you want `/health`.

Recommended release build:

```bash
cd mobile
flutter clean
flutter pub get
flutter build apk --release
```

The APK will use the Render URL automatically unless you explicitly provide another `API_BASE_URL`.
