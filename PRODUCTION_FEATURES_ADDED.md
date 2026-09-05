# Fast N Fresh — Production Feature Pack

## Added in this pack

- Kitchen Display Screen (KDS) with live NEW / PREPARING / READY queue.
- Staff QR-order alert with system alert sound when a new QR order is detected.
- QR order preparation estimate fields and customer live status support.
- Customer feedback: 1–5 star rating + optional comment after a completed QR order.
- Feedback API with rate limiting and admin/manager feedback listing.
- Admin/manager Audit Log screen.

## Already present and retained

- QR customer menu and table validation.
- Server-side pricing and stock validation.
- QR order live tracking.
- Product available/unavailable control.
- Inventory and low-stock tracking.
- Sales reports/dashboard.
- Expenses and customer/credit management.
- Table management and QR generation.
- Receipt PDF/print/share support.
- Staff/users/roles and attendance.
- Order cancellation/void workflow.
- Idempotent checkout/order submission.

## Deliberate production safeguards

- True offline paid billing is not silently simulated. The existing connectivity handling remains in place; offline billing needs a conflict-safe sync strategy before it should be enabled for real cafe sales.
- Flutter source changes must be compiled on a machine with the Flutter SDK before releasing the APK.
