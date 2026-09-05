# Fast N Fresh — Production Audit / Workflow Fix

## Verified from this ZIP

### Kitchen workflow
- Kitchen state is independent from payment state.
- QR orders enter Kitchen as `NEW` (`open`), then `PREPARING`, then `READY`.
- Kitchen never marks an order paid.
- Payment chips in Kitchen show only the payment method (`CASH` / `UPI`) rather than confusing `PENDING` payment state.
- Red is reserved for failure/cancellation; the Orders -> Kitchen badge is amber for NEW work.
- Ready orders expose `Open Bill` so billing/checkout can settle payment.
- Backend enforces the legal QR transitions: `open -> preparing -> ready`.
- Kitchen polling refreshes every 5 seconds and refreshes on app resume/connectivity recovery.

### QR + UPI safety
- Opening a UPI app or returning from it never marks an order paid.
- Customer must explicitly return to checkout and enter UPI reference/UTR before submitting an online-UPI order.
- QR orders start with `paymentStatus=pending` and zero financial payment breakdown.
- Only authenticated staff checkout changes the payment state to `paid`.
- Public order submission uses a client request idempotency key to prevent duplicate orders after retries/double taps.
- Public endpoints have rate limiting.

### Customer tracking
- Production static menu now starts customer order tracking after an order is successfully created.

### Theme / refresh
- Theme supports System / Light / Dark and persists the selection.
- Dashboard has an app-wide refresh action that refreshes session/catalog state and recreates all shell tabs so their data reloads without restarting Flutter.
- Dashboard continues to preserve last-known data if a refresh endpoint temporarily fails.

### Billing
- Receipt PDF contains cafe branding, bill number, date/time, order type, table/staff/customer, item/qty/amount, totals, payment method and payment status.
- Print/share use the existing `printing` flow and 58/80mm receipt sizing.

## Important production limitation

The ZIP does **not** contain a bank/PSP integration (Razorpay/PhonePe/Paytm/Cashfree/etc.) or webhook verification. Therefore the app deliberately does not pretend that a UPI app return is proof of payment. For automatic bank-verified UPI, connect a real payment provider and verify its server webhook/signature before setting `paymentStatus=paid`.

## Local verification

- Backend JavaScript syntax check: PASS for all backend JS files.
- Flutter `flutter analyze`, `flutter test`, and `flutter build apk --release` could not be executed in this environment because the Flutter SDK is not installed here. Run them on the Windows development machine before release.
