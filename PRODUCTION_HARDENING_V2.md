# Fast N Fresh — Production Hardening V2

Implemented on the supplied PRODUCTION_FIXED build.

## Reliability & security
- Request correlation IDs via `X-Request-Id`.
- API-wide rate limiting plus tighter public/login limits.
- Proxy-aware rate limiting for Render.
- Explicit CORS allow-list support; native mobile requests remain allowed.
- Central production-safe error responses include request ID, not stack traces.
- Graceful SIGTERM/SIGINT shutdown.
- Production secrets removed from distributable ZIP (`key.properties`, `.jks`).
- Added `backend/.env.example` and `mobile/android/key.properties.example`.

## Orders/payments
- Client request IDs validated before idempotency lookup.
- UPI UTR required for staff UPI checkout and mixed payments containing UPI.
- Reused paid UPI references are blocked.
- QR orders remain `pending` until authenticated checkout.
- QR order totals now include the same server-side tax settings used by checkout, preventing customer-vs-bill total mismatch.
- QR payment breakdown remains zero until settlement.

## Kitchen
- Kitchen state remains separate from payment state: NEW → PREPARING → READY → BILL/CHECKOUT.
- Payment is shown as a secondary chip, never as the kitchen state.

## Verification
- Backend JavaScript files are syntax-checkable with Node.
- Flutter APK/analyze/test could not be executed in this environment because Flutter SDK is unavailable here.
- Before release: run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release` on the Windows build machine.
